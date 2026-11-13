import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/schedule_catalog.dart';
import '../models/transport.dart';
import '../models/app_user.dart';
import 'schedule_repository.dart';
import 'attendance_repository.dart';
import 'schedule_selection_policy.dart';
import '../models/staff_absence.dart';
import 'staff_availability_diagnostics.dart';
import '../models/course_reassignment.dart';
import 'visit_time_calculator.dart';
import '../models/visit_time_review.dart';
import '../models/ai_schedule_suggestion.dart';
import '../models/schedule_codec.dart';
import '../models/schedule_changes.dart';

class ScheduleController extends ChangeNotifier {
  ScheduleController({
    required this.user,
    required this.catalog,
    DateTime? initialDate,
    DateTime Function()? clock,
    this.selectionPolicy = const ScheduleSelectionPolicy(),
    List<ScheduleSnapshot> initialConfirmed = const [],
  }) : _clock = clock ?? DateTime.now {
    final selection = selectionPolicy.select(_clock());
    final date = initialDate ?? selection.date;
    selectedDate = DateTime(date.year, date.month, date.day);
    period = initialDate == null ? selection.period : TransportPeriod.morning;
    // In-memory repository input for previews/tests. No server sync is implied.
    for (final snapshot in initialConfirmed) {
      if (snapshot.confirmedAt == null ||
          snapshot.version < 1 ||
          validate(snapshot).isNotEmpty) {
        throw ArgumentError('유효한 확정 일정만 불러올 수 있습니다.');
      }
      final key = _key(snapshot.date, snapshot.period);
      _confirmed[key] = snapshot;
      _drafts[key] = snapshot;
    }
    _ensureDraft();
  }

  ScheduleController.remote({
    required this.user,
    required ScheduleRepository repository,
    DateTime Function()? clock,
    void Function(String)? diagnosticLogger,
    this.selectionPolicy = const ScheduleSelectionPolicy(),
  }) : _clock = clock ?? DateTime.now,
       catalog = ScheduleCatalog.empty() {
    _repository = repository;
    _diagnosticLogger = diagnosticLogger;
    final selection = selectionPolicy.select(_clock());
    selectedDate = selection.date;
    period = selection.period;
    _connect();
  }

  ScheduleCatalog catalog;
  final DateTime Function() _clock;
  final ScheduleSelectionPolicy selectionPolicy;
  String get selectedScheduleLabel =>
      selectionPolicy.describe(selectedDate, period, _clock());
  ScheduleRepository? _repository;
  AttendanceRepository? get attendanceRepository =>
      _repository is AttendanceProvider
      ? (_repository as AttendanceProvider).attendance
      : null;
  StreamSubscription<ScheduleViewData>? _subscription;
  StreamSubscription<Map<String, StaffAbsence>>? _absenceSubscription;
  Timer? _availabilityTimer;
  void Function(String)? _diagnosticLogger;
  static const availabilityVerificationTimeout = Duration(seconds: 15);
  Map<String, StaffAbsence> absences = {};
  bool availabilityLoading = false;
  String? availabilityError;
  bool absenceSaving = false;
  String? absenceError;
  Map<String, dynamic>? _pendingAbsence;
  bool get supportsAbsences => _repository is StaffAvailabilityRepository;
  bool get busy => saving || absenceSaving;
  bool isStaffAbsent(String id) =>
      absences[id]?.periods.contains(period) ?? false;
  bool staffAvailable(Staff staff) =>
      staff.isAvailable(selectedDate, period) && !isStaffAbsent(staff.id);
  bool get reassignmentNeeded =>
      draft.routes.any((r) => isStaffAbsent(r.staffId));
  bool get confirmedReassignmentNeeded =>
      confirmed?.routes.any((r) => isStaffAbsent(r.staffId)) ?? false;
  String get absenceRevisionKey =>
      (absences.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => '${e.key}:${e.value.version}')
          .join('|');
  final Map<String, ScheduleCatalog> _catalogs = {};
  final Map<String, int> _baseVersions = {};
  final Map<
    String,
    ({
      ScheduleSnapshot snapshot,
      String id,
      Map<String, int>? availabilityVersions,
    })
  >
  _requests = {};
  int _generation = 0;
  bool _disposed = false;
  bool loading = false;
  bool saving = false;
  bool conflict = false;
  String? dataError;
  String? saveError;
  bool get isRemote => _repository != null;
  bool suggesting = false;
  bool get supportsAiSuggestions =>
      _repository is ScheduleSuggestionRepository &&
      (_repository as ScheduleSuggestionRepository).allowsAiSuggestions;

  bool isSuggestionCurrent(AiScheduleSuggestion suggestion) =>
      !_disposed &&
      !busy &&
      !loading &&
      !conflict &&
      dataError == null &&
      !availabilityLoading &&
      availabilityError == null &&
      identical(draft, suggestion.origin) &&
      identical(confirmed, suggestion.confirmed) &&
      identical(catalog, suggestion.catalog) &&
      absenceRevisionKey == suggestion.absenceRevision &&
      _generation == suggestion.generation;

  List<String> suggestionAssignmentErrors(ScheduleSnapshot candidate) =>
      validate(
        candidate.copyWith(
          routes: [
            for (final r in candidate.routes)
              r.copyWith(estimatedVisitMinutes: {}, estimatedVisitSources: {}),
          ],
        ),
      );

  Future<AiScheduleSuggestion> requestAiSuggestion() async {
    _requireAdmin();
    if (!supportsAiSuggestions || suggesting || conflict) {
      throw StateError('Emulator 연결과 최신 일정 상태를 확인해 주세요.');
    }
    final origin = draft;
    final baseline = confirmed;
    final originalCatalog = catalog;
    final revision = absenceRevisionKey;
    final generation = _generation;
    suggesting = true;
    notifyListeners();
    try {
      final result = await (_repository as ScheduleSuggestionRepository)
          .suggestSchedule({
            ...scheduleToJson(origin),
            'catalogVersion': originalCatalog.version,
            'expectedVersion': baseline?.version ?? 0,
            'requestId': 'ai-suggestion',
            'expectedAvailabilityVersions': {
              for (final s in originalCatalog.staff)
                s.id: absences[s.id]?.version ?? 0,
            },
          });
      final suggestion = AiScheduleSuggestion.fromJson(
        result,
        origin: origin,
        catalog: originalCatalog,
        confirmed: baseline,
        absenceRevision: revision,
        generation: generation,
      );
      if (!isSuggestionCurrent(suggestion)) {
        throw StateError('추천 중 일정 또는 결근 상태가 변경되었습니다. 다시 요청해 주세요.');
      }
      if (suggestionAssignmentErrors(suggestion.candidate).isNotEmpty) {
        throw StateError('AI 추천안의 배정 검증에 실패했습니다. 기존 일정은 유지됩니다.');
      }
      return suggestion;
    } on FirebaseFunctionsException catch (error) {
      throw StateError(switch (error.code) {
        'aborted' => '추천 중 일정 또는 결근 상태가 변경되었습니다. 다시 요청해 주세요.',
        'permission-denied' => '관리자만 AI 일정 제안을 사용할 수 있습니다.',
        'failed-precondition' =>
          'Emulator 가상 데이터와 서버의 GEMINI_API_KEY·GEMINI_MODEL 설정을 확인해 주세요.',
        'invalid-argument' =>
          error.details is Map &&
                  error.details['violation'] == 'REASSIGNMENT_NOT_JUSTIFIED'
              ? '코스를 옮길 만큼 추가 이득이 확인되지 않았습니다. 기존 코스를 유지해 다시 제안받거나 방문 순서만 조정해 주세요.'
              : 'AI 추천안이 업무 규칙을 충족하지 못했습니다. 기존 일정은 유지됩니다.',
        'resource-exhausted' => 'Gemini 사용 한도를 확인하고 잠시 후 다시 요청해 주세요.',
        _ => 'AI 요청에 실패했습니다. 네트워크와 서버 API 설정을 확인해 주세요. 기존 일정은 유지됩니다.',
      });
    } on FormatException {
      throw StateError('AI 응답 형식이 올바르지 않습니다. 기존 일정은 유지됩니다.');
    } on TypeError {
      throw StateError('AI 응답 형식이 올바르지 않습니다. 기존 일정은 유지됩니다.');
    } finally {
      if (!_disposed) {
        suggesting = false;
        notifyListeners();
      }
    }
  }

  void applyAiSuggestion(AiScheduleSuggestion suggestion) {
    _requireAdmin();
    if (!supportsAiSuggestions || !isSuggestionCurrent(suggestion)) {
      throw StateError('추천 대상 일정 또는 결근 상태가 변경되었습니다. 다시 요청해 주세요.');
    }
    if (suggestionAssignmentErrors(suggestion.candidate).isNotEmpty) {
      throw StateError('AI 추천안의 배정 검증에 실패했습니다.');
    }
    if (ScheduleChanges.compare(
      draft,
      suggestion.candidate,
      catalog,
    ).items.isEmpty) {
      return;
    }
    _update(suggestion.candidate);
  }

  Future<bool> setStaffAbsence(
    String staffId,
    Set<TransportPeriod> periods,
    bool absent,
    int expectedVersion,
  ) async {
    _requireAdmin();
    if (!supportsAbsences || periods.isEmpty) {
      throw StateError('결근 저장소 연결과 시간대를 확인해 주세요.');
    }
    final day = dateKey(selectedDate);
    final names = periods.map((p) => p.name).toList()..sort();
    final previous = _pendingAbsence;
    final request =
        previous != null &&
            previous['date'] == day &&
            previous['staffId'] == staffId &&
            previous['absent'] == absent &&
            listEquals(List<String>.from(previous['periods'] as List), names)
        ? previous
        : <String, dynamic>{
            'date': day,
            'staffId': staffId,
            'periods': names,
            'absent': absent,
            'expectedVersion': expectedVersion,
            'catalogVersion': catalog.version,
            'requestId': List.generate(
              16,
              (_) => Random.secure()
                  .nextInt(256)
                  .toRadixString(16)
                  .padLeft(2, '0'),
            ).join(),
          };
    _pendingAbsence = request;
    absenceSaving = true;
    absenceError = null;
    notifyListeners();
    try {
      final result = await (_repository! as StaffAvailabilityRepository)
          .setAbsence(request);
      if (_disposed) return false;
      if (day == dateKey(selectedDate) &&
          (absences[staffId]?.version ?? 0) <= result.version) {
        absences = Map.unmodifiable({...absences, staffId: result});
      }
      _pendingAbsence = null;
      return true;
    } catch (error) {
      if (!_disposed) {
        if (error is FirebaseFunctionsException &&
            [
              'aborted',
              'permission-denied',
              'invalid-argument',
              'failed-precondition',
              'already-exists',
            ].contains(error.code)) {
          _pendingAbsence = null;
          absenceError = error.code == 'aborted'
              ? '다른 관리자가 결근 상태를 변경했습니다. 최신 상태를 확인하고 다시 요청해 주세요.'
              : '결근을 저장하지 못했습니다. 관리자 권한과 직원 정보를 확인해 주세요.';
        } else {
          absenceError =
              '결근 저장 응답을 확인하지 못했습니다. 최신 상태를 확인한 뒤 같은 요청을 다시 시도해 주세요.';
        }
      }
      return false;
    } finally {
      if (!_disposed) {
        absenceSaving = false;
        notifyListeners();
      }
    }
  }

  void _connect() {
    final repository = _repository!;
    final generation = ++_generation;
    _subscription?.cancel();
    _absenceSubscription?.cancel();
    _availabilityTimer?.cancel();
    _availabilityTimer = null;
    absences = {};
    availabilityError = null;
    absenceError = null;
    final availabilityRepository = repository is StaffAvailabilityRepository
        ? repository as StaffAvailabilityRepository
        : null;
    availabilityLoading = availabilityRepository != null;
    if (availabilityRepository != null) {
      _waitForAvailability(generation);
      _absenceSubscription = availabilityRepository
          .watchAbsences(user, selectedDate)
          .listen(
            (values) {
              if (_disposed || generation != _generation) return;
              _availabilityTimer?.cancel();
              _availabilityTimer = null;
              final merged = Map<String, StaffAbsence>.from(values);
              for (final entry in absences.entries) {
                if ((merged[entry.key]?.version ?? 0) < entry.value.version) {
                  merged[entry.key] = entry.value;
                }
              }
              absences = Map.unmodifiable(merged);
              availabilityLoading = false;
              availabilityError = null;
              logStaffAvailability(
                values.isEmpty
                    ? 'read_succeeded state=verified-empty'
                    : 'read_succeeded state=verified documents=${values.length}',
                logger: _diagnosticLogger,
              );
              notifyListeners();
            },
            onError: (Object error) {
              if (_disposed || generation != _generation) return;
              if (error is StaffAvailabilityUnverified) {
                _waitForAvailability(generation);
                logStaffAvailability(
                  'read_waiting',
                  error: error,
                  logger: _diagnosticLogger,
                );
              } else {
                _availabilityTimer?.cancel();
                _availabilityTimer = null;
                availabilityLoading = false;
                availabilityError = staffAvailabilityErrorMessage(error);
                logStaffAvailability(
                  'read_failed',
                  error: error,
                  logger: _diagnosticLogger,
                );
              }
              notifyListeners();
            },
          );
    }
    loading = true;
    dataError = null;
    saveError = null;
    conflict = false;
    _subscription = repository
        .watch(user, selectedDate, period)
        .listen(
          (view) {
            if (_disposed || generation != _generation) return;
            try {
              _accept(view);
            } catch (_) {
              dataError = '서버 일정의 형식 또는 참조 정보가 올바르지 않습니다.';
            }
            loading = false;
            notifyListeners();
          },
          onError: (Object error) {
            if (_disposed || generation != _generation) return;
            loading = false;
            dataError = '일정을 불러올 수 없습니다. 네트워크·사용 권한·기본 데이터 등록 상태를 확인해 주세요.';
            notifyListeners();
          },
        );
  }

  void _waitForAvailability(int generation) {
    availabilityLoading = true;
    availabilityError = null;
    _availabilityTimer ??= Timer(availabilityVerificationTimeout, () {
      if (_disposed || generation != _generation) return;
      _availabilityTimer = null;
      final error = TimeoutException(
        'No verified server snapshot within 15 seconds',
      );
      availabilityLoading = false;
      availabilityError = staffAvailabilityErrorMessage(error);
      logStaffAvailability(
        'read_failed',
        error: error,
        logger: _diagnosticLogger,
      );
      notifyListeners();
    });
  }

  void _accept(ScheduleViewData view, {bool discardDraft = false}) {
    final key = _currentKey;
    final previousCatalog = _catalogs[key];
    final dirty = hasPendingChanges && !discardDraft;
    if (dirty) {
      final ownRequest =
          view.lastRequestId != null &&
          view.lastRequestId == _requests[key]?.id;
      conflict =
          !ownRequest &&
          ((view.confirmed?.version ?? 0) != _baseVersions[key] ||
              previousCatalog?.version != view.catalog.version);
      if (view.confirmed == null) {
        _confirmed.remove(key);
      } else {
        _confirmed[key] = view.confirmed!;
      }
      catalog = previousCatalog!;
    } else {
      catalog = view.catalog;
      _catalogs[key] = catalog;
      if (view.confirmed != null &&
          validate(view.confirmed!, checkAbsences: false).isNotEmpty) {
        throw const FormatException('Invalid confirmed schedule');
      }
      _baseVersions[key] = view.confirmed?.version ?? 0;
      if (view.confirmed == null) {
        _confirmed.remove(key);
      } else {
        _confirmed[key] = view.confirmed!;
      }
      _drafts.remove(key);
      if (view.confirmed != null) {
        _drafts[key] = view.confirmed!;
      } else if (role == UserRole.admin) {
        _ensureDraft();
      } else {
        _drafts[key] = ScheduleSnapshot(
          date: selectedDate,
          period: period,
          routes: [],
        );
      }
      _dirty.remove(key);
      _timeReviews.remove(key);
      _removedVisitEstimates.remove(key);
      conflict = false;
    }
    dataError = null;
  }

  void retryLoad() {
    if (_repository != null) {
      _connect();
      notifyListeners();
    }
  }

  Future<void> reloadDiscardingDraft() async {
    if (busy || _repository == null) return;
    final generation = ++_generation;
    final subscription = _subscription;
    _subscription = null;
    loading = true;
    notifyListeners();
    try {
      await subscription?.cancel();
      final view = await _repository!.load(user, selectedDate, period);
      if (_disposed || generation != _generation) return;
      _accept(view, discardDraft: true);
      _requests.remove(_currentKey);
      saveError = null;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        dataError = '최신 일정을 불러오지 못했습니다. 편집 내용은 유지됩니다.';
      }
    }
    if (!_disposed && generation == _generation) {
      loading = false;
      if (dataError == null) _connect();
      notifyListeners();
    }
  }

  Future<bool> publish() async {
    _requireAdmin();
    if (_repository == null) {
      confirm();
      return true;
    }
    if (loading || dataError != null || conflict) return false;
    if (confirmationErrors.isNotEmpty) {
      saveError = confirmationErrors.join('\n');
      notifyListeners();
      return false;
    }
    final key = _currentKey;
    final snapshot = draft;
    final previous = _requests[key];
    final requestId = previous != null && identical(previous.snapshot, snapshot)
        ? previous.id
        : List.generate(
            16,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
    final availabilityVersions =
        previous != null && identical(previous.snapshot, snapshot)
        ? previous.availabilityVersions
        : supportsAbsences
        ? {
            for (final route in snapshot.routes)
              route.staffId: absences[route.staffId]?.version ?? 0,
          }
        : null;
    _requests[key] = (
      snapshot: snapshot,
      id: requestId,
      availabilityVersions: availabilityVersions,
    );
    final expected = _baseVersions[key] ?? 0;
    final catalogVersion = catalog.version;
    saving = true;
    saveError = null;
    notifyListeners();
    var saved = false;
    try {
      try {
        if (availabilityVersions != null) {
          await (_repository! as StaffAvailabilityRepository)
              .publishWithAvailability(
                snapshot,
                catalogVersion,
                expected,
                requestId,
                availabilityVersions,
              );
        } else {
          await _repository!.publish(
            snapshot,
            catalogVersion,
            expected,
            requestId,
          );
        }
        saved = true;
      } catch (error) {
        // A network response can be lost AFTER the atomic commit succeeded.
        // Only a server receipt can resolve this ambiguity; retain request ID.
        if (error is FirebaseFunctionsException &&
            [
              'aborted',
              'permission-denied',
              'invalid-argument',
              'failed-precondition',
              'already-exists',
            ].contains(error.code)) {
          rethrow;
        }
        saved = await _repository!.committed(
          snapshot.date,
          snapshot.period,
          requestId,
        );
        if (!saved) rethrow;
      }
      final view = await _repository!.load(
        user,
        snapshot.date,
        snapshot.period,
      );
      if (_disposed) return saved;
      _accept(view, discardDraft: true);
      _requests.remove(key);
    } catch (error) {
      if (_disposed) return saved;
      if (error is FirebaseFunctionsException && error.code == 'aborted') {
        conflict = true;
        saveError = '다른 관리자가 일정을 변경했습니다. 편집 내용은 유지됩니다. 최신본을 확인해 주세요.';
      } else {
        saveError = saved
            ? '저장은 완료됐으나 최신 데이터를 확인하지 못했습니다. 다시 불러와 주세요.'
            : switch (error) {
                FirebaseFunctionsException(code: 'permission-denied') =>
                  '일정 저장 권한이 없습니다. 관리자 계정과 활성 상태를 확인해 주세요.',
                FirebaseFunctionsException(code: 'invalid-argument') =>
                  '서버 일정 검증에 실패했습니다. 근무·정원·중복 배정·예상 시각을 확인해 주세요.',
                FirebaseFunctionsException(
                  code: 'failed-precondition',
                  details: final details,
                )
                    when details is Map &&
                        details['reason'] == 'existing-schedule-incompatible' =>
                  '기존 일정의 형식 또는 추가 필드를 확인해 주세요. 서버 원본과 편집 초안은 보존됩니다. 별도 검토·변환 전에는 덮어쓸 수 없습니다.',
                FirebaseFunctionsException(code: 'failed-precondition') =>
                  '결근 상태 또는 기본 데이터 등록 상태를 확인해 주세요. 결근 직원의 코스는 재배정한 뒤 확정해야 합니다.',
                _ => '일정 저장에 실패했습니다. 편집 내용은 유지됩니다. 네트워크·권한을 확인하고 다시 시도해 주세요.',
              };
      }
    } finally {
      if (!_disposed) {
        saving = false;
        notifyListeners();
      }
    }
    return saved;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _subscription?.cancel();
    _absenceSubscription?.cancel();
    _availabilityTimer?.cancel();
    super.dispose();
  }

  late DateTime selectedDate;
  TransportPeriod period = TransportPeriod.morning;
  final AppUser user;
  UserRole get role => user.role;
  String? get staffId => user.staffId;
  final Map<String, ScheduleSnapshot> _drafts = {};
  final Map<String, ScheduleSnapshot> _confirmed = {};
  final Set<String> _dirty = {};
  // Local workflow state belongs to the same date/period draft. Never serialize
  // it as proof of authorization or as a server validation exemption.
  final Map<String, Map<String, VisitTimeReview>> _timeReviews = {};
  // Restore values excluded in this unconfirmed draft without silently losing
  // a manual/legacy estimate. Confirm/reload discards this temporary history.
  final Map<String, Map<String, ({int minute, String? source})>>
  _removedVisitEstimates = {};
  Map<String, VisitTimeReview> get timeReviews =>
      Map.unmodifiable(_timeReviews[_currentKey] ?? {});
  Set<String> get pendingTimeReviewRouteIds => Set.unmodifiable(
    timeReviews.entries
        .where((e) => e.value.decision == VisitTimeReviewDecision.pending)
        .map((e) => e.key),
  );
  List<String> get timeReviewErrors => [
    for (final id in pendingTimeReviewRouteIds)
      '${baseRoute(id).name}: 예상 시각 재검토 필요. 계산 결과 적용 또는 기존 시각 유지를 선택해 주세요.',
  ];
  List<String> get confirmationErrors => [
    ...validationErrors,
    ...timeReviewErrors,
  ];

  String _key(DateTime date, TransportPeriod period) =>
      '${dateKey(date)}/${period.name}';
  String get _currentKey => _key(selectedDate, period);
  ScheduleSnapshot get draft => _drafts[_currentKey]!;
  ScheduleSnapshot? get confirmed => _confirmed[_currentKey];
  bool get hasPendingChanges => _dirty.contains(_currentKey);

  BaseRoute baseRoute(String id) =>
      catalog.baseRoutes.firstWhere((r) => r.id == id);
  Staff staff(String id) => catalog.staff.firstWhere((s) => s.id == id);
  Passenger passenger(String id) =>
      catalog.passengers.firstWhere((p) => p.id == id);
  Vehicle vehicle(String id) => catalog.vehicles.firstWhere((v) => v.id == id);

  void _ensureDraft() {
    _drafts.putIfAbsent(
      _currentKey,
      () => ScheduleSnapshot(
        date: selectedDate,
        period: period,
        routes: [
          for (final r in catalog.baseRoutes.where((r) => r.period == period))
            RouteAssignment(
              baseRouteId: r.id,
              staffId: r.staffId,
              vehicleId: r.vehicleId,
              passengerIds: r.passengerIds,
            ),
        ],
      ),
    );
  }

  void selectDate(DateTime date) {
    _selectSchedule(date, period);
  }

  void selectPeriod(TransportPeriod value) {
    _selectSchedule(selectedDate, value);
  }

  /// Explicit, one-shot return to the operating policy; never a background timer.
  void selectCurrentSchedule() {
    if (busy) return;
    final selection = selectionPolicy.select(_clock());
    _selectSchedule(selection.date, selection.period);
  }

  void _selectSchedule(DateTime date, TransportPeriod value) {
    if (busy) return;
    final target = DateTime(date.year, date.month, date.day);
    if (target == selectedDate && value == period) return;
    selectedDate = target;
    period = value;
    if (_repository == null) {
      _ensureDraft();
    } else {
      _connect();
    }
    notifyListeners();
  }

  void _requireAdmin() {
    if (role != UserRole.admin) {
      throw StateError('관리자만 일정을 수정하고 확정할 수 있습니다.');
    }
    if (busy ||
        loading ||
        dataError != null ||
        availabilityLoading ||
        availabilityError != null) {
      throw StateError('일정을 처리 중이거나 서버 데이터를 확인할 수 없습니다.');
    }
  }

  void _update(
    ScheduleSnapshot snapshot, {
    Set<String> timeReviewedRoutes = const {},
  }) {
    _requireAdmin();
    final reviews = _timeReviews.putIfAbsent(_currentKey, () => {});
    for (final next in snapshot.routes) {
      final old = draft.routes
          .where((r) => r.baseRouteId == next.baseRouteId)
          .firstOrNull;
      if (old == null) continue;
      final reasons = <String>{};
      if (!listEquals(old.passengerIds, next.passengerIds)) {
        if (setEquals(old.passengerIds.toSet(), next.passengerIds.toSet())) {
          reasons.add('방문 순서 변경');
        } else {
          if (next.passengerIds.any((id) => !old.passengerIds.contains(id))) {
            reasons.add('이용자 추가·복귀·도착');
          }
          if (old.passengerIds.any((id) => !next.passengerIds.contains(id))) {
            reasons.add('이용자 제외·결석·출발');
          }
        }
      }
      if (old.staffId != next.staffId) reasons.add('담당 직원 변경·코스 인계');
      final previous = reviews[next.baseRouteId];
      if (previous != null &&
          (!mapEquals(old.estimatedVisitMinutes, next.estimatedVisitMinutes) ||
              !mapEquals(
                old.estimatedVisitSources,
                next.estimatedVisitSources,
              ) ||
              old.startMinute != next.startMinute ||
              old.endMinute != next.endMinute)) {
        reasons.add('시각·운행 구간 변경');
      }
      if (reasons.isNotEmpty) {
        reviews[next.baseRouteId] = VisitTimeReview(
          VisitTimeReviewDecision.pending,
          {
            if (previous?.decision == VisitTimeReviewDecision.pending)
              ...previous!.reasons,
            ...reasons,
          },
        );
      }
    }
    _drafts[_currentKey] = snapshot;
    _dirty.add(_currentKey);
    for (final id in timeReviewedRoutes) {
      final review = reviews[id];
      if (review != null) {
        reviews[id] = VisitTimeReview(
          VisitTimeReviewDecision.applied,
          review.reasons,
        );
      }
    }
    notifyListeners();
  }

  void keepVisitTimes(String routeId, {ScheduleSnapshot? expectedSnapshot}) {
    _requireAdmin();
    if (conflict ||
        (expectedSnapshot != null && !identical(draft, expectedSnapshot))) {
      throw StateError('일정이 변경되었습니다. 최신 시각을 다시 검토해 주세요.');
    }
    final route = draft.routes.firstWhere((r) => r.baseRouteId == routeId);
    final warnings = visitTimeWarnings(route, route.estimatedVisitMinutes);
    if (warnings.isNotEmpty) throw StateError(warnings.join('\n'));
    final review = _timeReviews[_currentKey]?[routeId];
    if (review == null) return;
    _timeReviews[_currentKey]![routeId] = VisitTimeReview(
      VisitTimeReviewDecision.kept,
      review.reasons,
    );
    notifyListeners();
  }

  void markAbsent(String passengerId) =>
      excludePassenger(passengerId, absent: true);

  void excludePassenger(String passengerId, {bool absent = false}) {
    _requireAdmin();
    passenger(passengerId);
    if (!draft.routes.any((r) => r.passengerIds.contains(passengerId))) {
      throw StateError('현재 일정에 배정된 이용자만 결석 처리할 수 있습니다.');
    }
    final previous = draft.routes.firstWhere(
      (r) => r.passengerIds.contains(passengerId),
    );
    final saved = _removedVisitEstimates.putIfAbsent(_currentKey, () => {});
    final minute = previous.estimatedVisitMinutes[passengerId];
    if (minute == null) {
      saved.remove(passengerId);
    } else {
      saved[passengerId] = (
        minute: minute,
        source: previous.estimatedVisitSources[passengerId],
      );
    }
    _update(
      draft.copyWith(
        absentIds: {...draft.absentIds, if (absent) passengerId},
        excludedIds: {...draft.excludedIds, if (!absent) passengerId},
        routes: [
          for (final r in draft.routes)
            r.copyWith(
              passengerIds: r.passengerIds
                  .where((id) => id != passengerId)
                  .toList(),
              estimatedVisitMinutes: {...r.estimatedVisitMinutes}
                ..remove(passengerId),
              estimatedVisitSources: {...r.estimatedVisitSources}
                ..remove(passengerId),
            ),
        ],
      ),
    );
  }

  void restorePassenger(String passengerId) {
    _requireAdmin();
    if (!draft.absentIds.contains(passengerId) &&
        !draft.excludedIds.contains(passengerId)) {
      return;
    }
    final original = catalog.baseRoutes.firstWhere(
      (r) => r.period == period && r.passengerIds.contains(passengerId),
    );
    addPassenger(passengerId, original.id);
  }

  /// Add/restore an existing passenger, or move them atomically from another
  /// staff member. Existing estimates move unchanged and require review.
  void addPassenger(String passengerId, String targetRouteId) {
    _requireAdmin();
    passenger(passengerId);
    if (!catalog.baseRoutes
            .where((r) => r.period == period)
            .any((r) => r.passengerIds.contains(passengerId)) ||
        !draft.routes.any((r) => r.baseRouteId == targetRouteId)) {
      throw StateError('대상 시간대의 이용자와 배정 코스를 확인해 주세요.');
    }
    if (draft.routes
        .firstWhere((r) => r.baseRouteId == targetRouteId)
        .passengerIds
        .contains(passengerId)) {
      return;
    }
    final previous = draft.routes
        .where((r) => r.passengerIds.contains(passengerId))
        .firstOrNull;
    final saved = _removedVisitEstimates[_currentKey]?[passengerId];
    final minute =
        previous?.estimatedVisitMinutes[passengerId] ?? saved?.minute;
    final source = previous == null
        ? saved?.source
        : previous.estimatedVisitSources[passengerId];
    _removedVisitEstimates[_currentKey]?.remove(passengerId);
    _update(
      draft.copyWith(
        absentIds: {...draft.absentIds}..remove(passengerId),
        excludedIds: {...draft.excludedIds}..remove(passengerId),
        routes: [
          for (final r in draft.routes)
            r.copyWith(
              passengerIds: [
                ...r.passengerIds.where((id) => id != passengerId),
                if (r.baseRouteId == targetRouteId) passengerId,
              ],
              estimatedVisitMinutes: {
                ...({...r.estimatedVisitMinutes}..remove(passengerId)),
                if (r.baseRouteId == targetRouteId && minute != null)
                  passengerId: minute,
              },
              estimatedVisitSources: {
                ...({...r.estimatedVisitSources}..remove(passengerId)),
                if (r.baseRouteId == targetRouteId &&
                    minute != null &&
                    source != null)
                  passengerId: source,
              },
            ),
        ],
      ),
    );
  }

  void setVisitMinute(String routeId, String passengerId, int? minute) {
    _requireAdmin();
    final route = draft.routes.firstWhere((r) => r.baseRouteId == routeId);
    if (!route.passengerIds.contains(passengerId)) {
      throw StateError('현재 코스의 이용자만 시각을 입력할 수 있습니다.');
    }
    final times = {...route.estimatedVisitMinutes}..remove(passengerId);
    final sources = {...route.estimatedVisitSources}..remove(passengerId);
    if (minute != null) times[passengerId] = minute;
    if (minute != null) sources[passengerId] = 'manual';
    _replaceRoute(
      route.copyWith(
        estimatedVisitMinutes: times,
        estimatedVisitSources: sources,
      ),
    );
  }

  void applyVisitTimePreview(
    VisitTimePreview preview, {
    bool manualOverwriteConfirmed = false,
  }) {
    _requireAdmin();
    if (conflict || !identical(draft, preview.snapshot)) {
      throw StateError('일정이 변경되었습니다. 최신 방문 순서로 다시 계산해 주세요.');
    }
    if (preview.warnings.isNotEmpty) throw StateError('시각 충돌을 해결한 뒤 적용해 주세요.');
    final manualChanges = preview.route.passengerIds.where(
      (id) =>
          preview.route.isManualEstimate(id) &&
          preview.route.estimatedVisitMinutes[id] != preview.result[id],
    );
    if (manualChanges.isNotEmpty && !manualOverwriteConfirmed) {
      throw StateError('수동 시각 변경을 별도로 확인해야 합니다.');
    }
    if (mapEquals(preview.route.estimatedVisitMinutes, preview.result) &&
        preview.route.passengerIds.every(
          (id) =>
              (preview.route.estimatedVisitSources[id] ?? 'manual') ==
              (preview.sources[id] ?? 'manual'),
        )) {
      final review = _timeReviews[_currentKey]?[preview.route.baseRouteId];
      if (review != null) {
        _timeReviews[_currentKey]![preview.route.baseRouteId] = VisitTimeReview(
          VisitTimeReviewDecision.applied,
          review.reasons,
        );
        notifyListeners();
      }
      return;
    }
    _replaceRoute(
      preview.route.copyWith(
        estimatedVisitMinutes: preview.result,
        estimatedVisitSources: preview.sources,
      ),
      timeReviewed: true,
    );
  }

  VisitTimeBatchReview prepareVisitTimeBatch(
    Map<String, int> firstMinutes,
    int intervalMinutes,
  ) {
    _requireAdmin();
    if (intervalMinutes <= 0) throw ArgumentError('방문 간격을 1분 이상으로 입력해 주세요.');
    if (conflict || pendingTimeReviewRouteIds.isEmpty) {
      throw StateError('일정이 바뀌었습니다. 화면의 방문 시간을 다시 확인해 주세요.');
    }
    final ids = Set<String>.unmodifiable(pendingTimeReviewRouteIds);
    final previews = <VisitTimePreview>[];
    for (final r in draft.routes.where((r) => ids.contains(r.baseRouteId))) {
      if (r.passengerIds.isEmpty) continue;
      final first = firstMinutes[r.baseRouteId];
      if (first == null) {
        throw StateError('${baseRoute(r.baseRouteId).name}의 첫 방문 시간을 입력해 주세요.');
      }
      previews.add(
        previewVisitTimes(
          draft,
          r.baseRouteId,
          first,
          intervalMinutes,
          replaceManual: true,
        ),
      );
    }
    return VisitTimeBatchReview._(
      draft,
      catalog,
      absenceRevisionKey,
      _generation,
      ids,
      previews,
    );
  }

  bool isVisitTimeBatchCurrent(VisitTimeBatchReview review) =>
      !_disposed &&
      !busy &&
      !loading &&
      !conflict &&
      dataError == null &&
      !availabilityLoading &&
      availabilityError == null &&
      identical(review.snapshot, draft) &&
      identical(review.catalog, catalog) &&
      review.absenceRevision == absenceRevisionKey &&
      review.generation == _generation &&
      setEquals(review.routeIds, pendingTimeReviewRouteIds);

  void applyVisitTimeBatch(
    VisitTimeBatchReview review, {
    bool manualOverwriteConfirmed = false,
  }) {
    _requireAdmin();
    if (!isVisitTimeBatchCurrent(review)) {
      throw StateError('확인하는 동안 일정이나 결근 상태가 바뀌었습니다. 방문 시간을 다시 맞춰 주세요.');
    }
    if (review.previews.any((p) => p.warnings.isNotEmpty)) {
      throw StateError('첫 방문 시간을 앞당기거나 방문 간격을 줄인 뒤 다시 확인해 주세요.');
    }
    if (review.manualChanges > 0 && !manualOverwriteConfirmed) {
      throw StateError('직접 입력한 시간이 바뀝니다. 변경 내용을 확인해 주세요.');
    }
    final updated = {
      for (final p in review.previews)
        p.route.baseRouteId: p.route.copyWith(
          estimatedVisitMinutes: p.result,
          estimatedVisitSources: {
            for (final id in p.route.passengerIds)
              if (p.route.estimatedVisitMinutes[id] != p.result[id])
                id: p.sources[id]!
              else if (p.route.estimatedVisitSources.containsKey(id))
                id: p.route.estimatedVisitSources[id]!,
          },
        ),
    };
    _update(
      draft.copyWith(
        routes: [for (final r in draft.routes) updated[r.baseRouteId] ?? r],
      ),
      timeReviewedRoutes: review.routeIds,
    );
  }

  void setOperatingWindow(String routeId, int? start, int? end) {
    _requireAdmin();
    if ((start == null) != (end == null)) {
      throw StateError('예상 출발·종료 시각을 함께 입력해 주세요.');
    }
    final route = draft.routes.firstWhere((r) => r.baseRouteId == routeId);
    _replaceRoute(
      route.copyWith(
        startMinute: start,
        endMinute: end,
        clearOperatingWindow: start == null,
      ),
    );
  }

  void movePassenger(String passengerId, String targetRouteId) {
    _requireAdmin();
    if (!draft.routes.any((r) => r.baseRouteId == targetRouteId) ||
        !draft.routes.any((r) => r.passengerIds.contains(passengerId)) ||
        draft.absentIds.contains(passengerId)) {
      throw StateError('이용자와 이동할 코스를 확인해 주세요.');
    }
    if (draft.routes
        .firstWhere((r) => r.baseRouteId == targetRouteId)
        .passengerIds
        .contains(passengerId)) {
      return;
    }
    addPassenger(passengerId, targetRouteId);
  }

  void reorder(String routeId, int index, int delta) {
    _requireAdmin();
    final route = draft.routes.firstWhere((r) => r.baseRouteId == routeId);
    final ids = [...route.passengerIds];
    final target = index + delta;
    if (index < 0 ||
        index >= ids.length ||
        target < 0 ||
        target >= ids.length) {
      return;
    }
    final id = ids.removeAt(index);
    ids.insert(target, id);
    _replaceRoute(route.copyWith(passengerIds: ids));
  }

  void assign(String routeId, {String? staffId, String? vehicleId}) {
    _requireAdmin();
    final route = draft.routes.firstWhere((r) => r.baseRouteId == routeId);
    _replaceRoute(route.copyWith(staffId: staffId, vehicleId: vehicleId));
  }

  /// A-2 changes only the dated draft. Server publication stays explicit.
  void reassignAbsentCourse(String routeId, String targetStaffId) {
    _requireAdmin();
    if (conflict) throw StateError('최신 확정본을 확인한 뒤 다시 재배정해 주세요.');
    final route = draft.routes.firstWhere((r) => r.baseRouteId == routeId);
    final target = staff(targetStaffId);
    final reason = courseReassignmentBlockReason(
      catalog,
      draft,
      route,
      target,
      {
        for (final s in catalog.staff)
          if (isStaffAbsent(s.id)) s.id,
      },
    );
    if (reason != null) throw StateError(reason);
    _replaceRoute(route.copyWith(staffId: targetStaffId));
  }

  void _replaceRoute(RouteAssignment route, {bool timeReviewed = false}) =>
      _update(
        draft.copyWith(
          routes: [
            for (final r in draft.routes)
              if (r.baseRouteId == route.baseRouteId) route else r,
          ],
        ),
        timeReviewedRoutes: timeReviewed ? {route.baseRouteId} : const {},
      );

  /// Demo routes overlap for the entire period; sequential reuse is out of scope.
  List<String> validate(
    ScheduleSnapshot snapshot, {
    bool checkAbsences = true,
  }) {
    final errors = <String>[];
    final staffIds = <String>{};
    final vehicleIds = <String>{};
    final passengerIds = <String>{};
    final routeIds = <String>{};
    final expected = catalog.baseRoutes.where(
      (r) => r.period == snapshot.period,
    );
    final expectedPassengers = expected.expand((r) => r.passengerIds).toSet();
    final removedIds = {...snapshot.absentIds, ...snapshot.excludedIds};
    if (snapshot.absentIds.intersection(snapshot.excludedIds).isNotEmpty) {
      errors.add('결석과 제외 상태가 중복되었습니다.');
    }
    for (final id in removedIds) {
      if (!expectedPassengers.contains(id)) {
        errors.add('대상 시간대에 없는 결석 이용자입니다: $id');
      }
    }
    for (final r in snapshot.routes) {
      final bases = expected.where((b) => b.id == r.baseRouteId);
      final label = bases.isEmpty ? r.baseRouteId : bases.first.name;
      final start = r.startMinute;
      final end = r.endMinute;
      bool validMinute(int value) => value >= 0 && value < 24 * 60;
      if ((start == null) != (end == null) ||
          (start != null &&
              end != null &&
              (!validMinute(start) || !validMinute(end) || start >= end))) {
        errors.add('$label: 예상 운행 시작·종료 시각을 확인해 주세요.');
      }
      if (r.estimatedVisitMinutes.keys.any(
        (id) => !r.passengerIds.contains(id),
      )) {
        errors.add('$label: 배정되지 않은 이용자의 예상 시각이 남아 있습니다.');
      }
      if (r.estimatedVisitSources.entries.any(
        (entry) =>
            !r.estimatedVisitMinutes.containsKey(entry.key) ||
            !['manual', 'fixedInterval'].contains(entry.value),
      )) {
        errors.add('$label: 예상 시각 출처를 확인해 주세요.');
      }
      int? previous;
      for (final id in r.passengerIds) {
        final minute = r.estimatedVisitMinutes[id];
        if (minute == null) continue;
        if (!validMinute(minute) ||
            (start != null && minute < start) ||
            (end != null && minute > end)) {
          errors.add('$label: 예상 방문 시각이 운행 시간 범위를 벗어났습니다.');
        }
        if (previous != null && minute <= previous) {
          errors.add('$label: 방문 순서와 예상 방문 시각이 충돌합니다.');
        }
        previous = minute;
      }
      if (bases.isEmpty) errors.add('$label: 기본 코스와 시간대를 확인해 주세요.');
      if (!routeIds.add(r.baseRouteId)) errors.add('$label: 코스가 중복되었습니다.');
      final employees = catalog.staff.where((s) => s.id == r.staffId);
      if (checkAbsences &&
          dateKey(snapshot.date) == dateKey(selectedDate) &&
          snapshot.period == period &&
          isStaffAbsent(r.staffId)) {
        errors.add('$label: 결근 직원의 코스가 남아 있습니다. 재배정이 필요합니다.');
      }
      if (employees.isEmpty) {
        errors.add('$label: 존재하지 않는 직원입니다.');
      } else if (!employees.first.isAvailable(snapshot.date, snapshot.period)) {
        errors.add('$label: ${employees.first.name} 직원은 해당 날짜에 근무할 수 없습니다.');
      }
      if (!staffIds.add(r.staffId)) {
        errors.add('$label: 직원이 같은 시간대에 중복 배정되었습니다.');
      }
      final vehicles = catalog.vehicles.where((v) => v.id == r.vehicleId);
      if (vehicles.isEmpty) {
        errors.add('$label: 존재하지 않는 차량입니다.');
      } else if (r.passengerIds.length > vehicles.first.passengerCapacity) {
        errors.add(
          '$label: 차량 정원 ${vehicles.first.passengerCapacity}명을 초과했습니다.',
        );
      }
      if (!vehicleIds.add(r.vehicleId)) {
        errors.add('$label: 차량이 같은 시간대에 중복 배정되었습니다.');
      }
      for (final id in r.passengerIds) {
        if (!expectedPassengers.contains(id)) {
          errors.add('$label: 대상 시간대에 없는 이용자입니다: $id');
        }
        if (!passengerIds.add(id)) errors.add('$label: 이용자가 중복 배정되었습니다.');
        if (snapshot.absentIds.contains(id)) {
          errors.add('$label: 결석한 이용자가 포함되어 있습니다.');
        }
        if (snapshot.excludedIds.contains(id)) {
          errors.add('$label: 제외한 이용자가 포함되어 있습니다.');
        }
      }
    }
    if (!setEquals(routeIds, expected.map((r) => r.id).toSet())) {
      errors.add('기본 코스가 누락되었거나 다른 시간대의 코스가 포함되어 있습니다.');
    }
    if (!setEquals(passengerIds, expectedPassengers.difference(removedIds))) {
      errors.add('송영 대상 이용자의 누락 또는 잘못된 배정을 확인해 주세요.');
    }
    return errors;
  }

  List<String> get validationErrors => validate(draft);

  List<RouteAssignment> routesForStaff(String id) =>
      draft.routes.where((route) => route.staffId == id).toList();

  List<String> get planningWarnings => [
    for (final route in draft.routes)
      if (route.startMinute == null ||
          route.endMinute == null ||
          route.passengerIds.any(
            (id) => !route.estimatedVisitMinutes.containsKey(id),
          ))
        '${staff(route.staffId).name} · ${baseRoute(route.baseRouteId).name}: 예상 시각이 미입력된 항목이 있습니다.',
  ];

  void confirm() {
    if (_repository != null) throw StateError('서버 일정은 publish를 통해 확정해야 합니다.');
    _requireAdmin();
    final errors = confirmationErrors;
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));
    final snapshot = draft.copyWith(
      version: (confirmed?.version ?? 0) + 1,
      confirmedAt: DateTime.now(),
    );
    _confirmed[_currentKey] = snapshot;
    _drafts[_currentKey] = snapshot;
    _dirty.remove(_currentKey);
    _timeReviews.remove(_currentKey);
    _removedVisitEstimates.remove(_currentKey);
    notifyListeners();
  }

  List<RouteAssignment> get staffRoutes =>
      confirmed?.routes.where((r) => r.staffId == staffId).toList() ?? [];
}

/// A single immutable review for all changed courses of one date/period.
class VisitTimeBatchReview {
  VisitTimeBatchReview._(
    this.snapshot,
    this.catalog,
    this.absenceRevision,
    this.generation,
    this.routeIds,
    List<VisitTimePreview> previews,
  ) : previews = List.unmodifiable(previews);
  final ScheduleSnapshot snapshot;
  final ScheduleCatalog catalog;
  final String absenceRevision;
  final int generation;
  final Set<String> routeIds;
  final List<VisitTimePreview> previews;
  int get manualChanges =>
      previews.fold(0, (sum, p) => sum + p.manualChanges.length);
  int get changedTimes => previews.fold(
    0,
    (sum, p) =>
        sum +
        p.route.passengerIds
            .where((id) => p.route.estimatedVisitMinutes[id] != p.result[id])
            .length,
  );
}
