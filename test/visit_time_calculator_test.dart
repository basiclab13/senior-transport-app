import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/models/schedule_codec.dart';
import 'package:senior_transport_app/models/transport.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';
import 'package:senior_transport_app/services/visit_time_calculator.dart';

import 'support/fixtures.dart';

void main() {
  const calculator = FixedIntervalVisitTimeCalculator();
  for (final interval in [0, -1, -30]) {
    test(
      'rejects interval $interval',
      () => expect(
        () => calculator.calculate(['p1'], 480, interval),
        throwsArgumentError,
      ),
    );
  }
  test('current order, midnight equality and 23:59 boundary', () {
    expect(calculator.calculate(['p3', 'p1', 'p2'], 480, 7), {
      'p3': 480,
      'p1': 487,
      'p2': 494,
    });
    expect(calculator.calculate(['p1', 'p2'], 1438, 1), {
      'p1': 1438,
      'p2': 1439,
    });
    expect(
      () => calculator.calculate(['p1', 'p2'], 1439, 1),
      throwsArgumentError,
    );
    expect(
      () => calculator.calculate(['p1', 'p2'], 1400, 60),
      throwsArgumentError,
    );
    for (final minute in [-1, 1440]) {
      expect(
        () => calculator.calculate(['p1'], minute, 5),
        throwsArgumentError,
      );
    }
  });
  test('empty or duplicate visitors rejected', () {
    expect(() => calculator.calculate([], 480, 5), throwsArgumentError);
    expect(
      () => calculator.calculate(['p1', 'p1'], 480, 5),
      throwsArgumentError,
    );
  });

  late ScheduleController c;
  setUp(
    () => c = fixtureController(
      user: const AppUser(uid: 'admin', role: UserRole.admin),
    ),
  );
  tearDown(() => c.dispose());

  test('preview is pure; apply fills the route draft and records fixedInterval sources', () {
    final original = c.draft;
    final preview = previewVisitTimes(original, 'morning-a', 480, 5);
    expect(c.draft, same(original));
    expect(c.hasPendingChanges, isFalse);
    expect(preview.result, {'p1': 480, 'p2': 485, 'p3': 490});
    c.applyVisitTimePreview(preview);
    expect(c.confirmed, isNull);
    expect(c.draft.routes[0].estimatedVisitSources.values.toSet(), {
      'fixedInterval',
    });
    expect(c.draft.routes[1], same(original.routes[1]));
    expect(c.validationErrors, isEmpty);
    final encoded = routeToJson(c.draft.routes.first);
    expect(encoded['estimatedVisitSources'], {
      'p1': 'fixedInterval',
      'p2': 'fixedInterval',
      'p3': 'fixedInterval',
    });
  });
  test('legacy times with no source are manual and protected', () {
    final old = c.draft.routes.first.copyWith(
      estimatedVisitMinutes: {'p1': 475},
    );
    final snapshot = c.draft.copyWith(routes: [old, c.draft.routes[1]]);
    final preview = previewVisitTimes(snapshot, 'morning-a', 480, 5);
    expect(preview.calculated['p1'], 480);
    expect(preview.result['p1'], 475);
    expect(preview.protectedIds, {'p1'});
    expect(preview.sources['p1'], 'manual');
    expect(preview.manualChanges, isEmpty);
  });
  test('manual override requires controller confirmation; identical manual values stay manual', () {
    c.setVisitMinute('morning-a', 'p1', 475);
    final preview = previewVisitTimes(
      c.draft,
      'morning-a',
      480,
      5,
      replaceManual: true,
    );
    expect(() => c.applyVisitTimePreview(preview), throwsStateError);
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 475);
    c.applyVisitTimePreview(preview, manualOverwriteConfirmed: true);
    expect(c.draft.routes.first.estimatedVisitMinutes['p1'], 480);
    c.setVisitMinute('morning-a', 'p1', 480);
    final same = previewVisitTimes(
      c.draft,
      'morning-a',
      480,
      5,
      replaceManual: true,
    );
    expect(same.manualChanges, isEmpty);
    expect(same.sources['p1'], 'manual');
  });
  test(
    'automatic values can recalculate while manual values remain anchors',
    () {
      c.applyVisitTimePreview(previewVisitTimes(c.draft, 'morning-a', 480, 5));
      c.setVisitMinute('morning-a', 'p2', 490);
      final preview = previewVisitTimes(c.draft, 'morning-a', 485, 10);
      expect(preview.result, {'p1': 485, 'p2': 490, 'p3': 505});
      expect(preview.protectedIds, {'p2'});
      expect(preview.warnings, isEmpty);
      c.applyVisitTimePreview(preview);
      expect(c.draft.routes.first.estimatedVisitSources['p2'], 'manual');
    },
  );
  test(
    'manual conflict and operating-window collisions warn and block applying',
    () {
      c.setVisitMinute('morning-a', 'p2', 470);
      final conflict = previewVisitTimes(c.draft, 'morning-a', 480, 5);
      expect(conflict.warnings.join(), contains('역전'));
      expect(() => c.applyVisitTimePreview(conflict), throwsStateError);
      c.setVisitMinute('morning-a', 'p2', null);
      c.setOperatingWindow('morning-a', 490, 510);
      final range = previewVisitTimes(c.draft, 'morning-a', 480, 5);
      expect(range.warnings.join(), contains('운행'));
      expect(() => c.applyVisitTimePreview(range), throwsStateError);
    },
  );
  test('reordering warns about old times; recalculation previews corrected order without editing', () {
    c.applyVisitTimePreview(previewVisitTimes(c.draft, 'morning-a', 480, 5));
    c.reorder('morning-a', 0, 1);
    final original = c.draft;
    final preview = previewVisitTimes(original, 'morning-a', 480, 5);
    expect(preview.existingWarnings.join(), contains('역전'));
    expect(preview.warnings, isEmpty);
    expect(preview.result, {'p2': 480, 'p1': 485, 'p3': 490});
    expect(c.draft, same(original));
  });
  test('stale preview and another date/period are rejected', () {
    final preview = previewVisitTimes(c.draft, 'morning-a', 480, 5);
    c.reorder('morning-a', 0, 1);
    expect(() => c.applyVisitTimePreview(preview), throwsStateError);
    c.selectPeriod(TransportPeriod.afternoon);
    expect(() => c.applyVisitTimePreview(preview), throwsStateError);
    c.selectDate(DateTime(2026, 11, 13));
    expect(() => c.applyVisitTimePreview(preview), throwsStateError);
  });
  test('exclusion removes active values; passenger and course handoff preserve estimates and provenance', () {
    c.applyVisitTimePreview(previewVisitTimes(c.draft, 'morning-a', 480, 5));
    final times = c.draft.routes.first.estimatedVisitMinutes;
    c.assign('morning-a', staffId: 's3');
    expect(c.draft.routes.first.estimatedVisitMinutes, times);
    expect(c.draft.routes.first.estimatedVisitSources['p1'], 'fixedInterval');
    c.markAbsent('p2');
    expect(
      c.draft.routes.first.estimatedVisitSources.containsKey('p2'),
      isFalse,
    );
    c.movePassenger('p1', 'morning-b');
    expect(
      c.draft.routes.first.estimatedVisitSources.containsKey('p1'),
      isFalse,
    );
    expect(c.draft.routes.last.estimatedVisitSources['p1'], 'fixedInterval');
    expect(c.draft.routes.last.estimatedVisitMinutes['p1'], 480);
  });
  test('empty-source legacy codec compatibility and new source round trip', () {
    c.confirm();
    final legacy = {
      ...scheduleToJson(c.confirmed!),
      'schemaVersion': 1,
      'status': 'confirmed',
      'timezone': 'Asia/Seoul',
      'version': 1,
    };
    final decoded = scheduleFromJson(legacy, DateTime(2026));
    expect(decoded.routes.first.estimatedVisitSources, isEmpty);
    c.applyVisitTimePreview(previewVisitTimes(c.draft, 'morning-a', 480, 5));
    final current = {
      ...scheduleToJson(c.draft),
      'schemaVersion': 1,
      'status': 'confirmed',
      'timezone': 'Asia/Seoul',
      'version': 2,
    };
    expect(
      scheduleFromJson(
        current,
        DateTime(2026),
      ).routes.first.estimatedVisitSources['p1'],
      'fixedInterval',
    );
  });
  test('staff cannot apply bulk times', () {
    final staff = fixtureController(
      user: const AppUser(uid: 'staff', role: UserRole.staff, staffId: 's1'),
    );
    expect(
      () => staff.applyVisitTimePreview(
        previewVisitTimes(staff.draft, 'morning-a', 480, 5),
      ),
      throwsStateError,
    );
    staff.dispose();
  });
}
