import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senior_transport_app/models/app_user.dart';
import 'package:senior_transport_app/screens/schedule_screen.dart';
import 'package:senior_transport_app/services/schedule_controller.dart';

import 'support/fixtures.dart';

void main() {
  testWidgets(
    '40 employees / 79 passengers: search, edit, reassign and confirm all staff',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const user = AppUser(uid: 'fictional-admin', role: UserRole.admin);
      final catalog = largeCatalog();
      final repository = MemoryScheduleRepository(catalog: catalog);
      final c = ScheduleController.remote(user: user, repository: repository);
      addTearDown(c.dispose);
      addTearDown(repository.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            user: user,
            controller: c,
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.catalog.staff.length, 40);
      expect(c.catalog.passengers.length, 79);
      await tester.enterText(find.byKey(const Key('staff-search')), '가상 직원 40');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('staff-s40')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staff-detail-s40')), findsOneWidget);
      expect(find.text('가상 40코스'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('staff-search')), '김다정');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('staff-s1')));
      await tester.pumpAndSettle();
      final absent = find.byKey(const ValueKey('absent-p2'));
      await tester.ensureVisible(absent);
      await tester.pumpAndSettle();
      await tester.tap(absent);
      await tester.pumpAndSettle();
      c.movePassenger('p78', 'morning-a');
      c.setVisitMinute('morning-a', 'p78', 520);
      await tester.pumpAndSettle();
      expect(c.routesForStaff('s40').single.passengerIds, ['p79']);
      expect(c.validationErrors, isEmpty);
      await tester.tap(find.byKey(const Key('confirm-schedule')));
      await tester.pumpAndSettle();
      expect(c.confirmed, isNull);
      await tester.tap(find.byKey(const Key('approve-confirm')));
      await tester.pumpAndSettle();
      expect(c.confirmed!.routes.length, 39);
      expect(c.confirmed!.routes.first.passengerIds, ['p1', 'p3', 'p78']);
      expect(repository.requests.length, 1);
      expect(c.hasPendingChanges, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
