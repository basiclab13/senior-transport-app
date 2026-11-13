import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/transport.dart';
import '../services/schedule_controller.dart';
import '../services/schedule_repository.dart';
import '../services/schedule_selection_policy.dart';
import '../models/schedule_changes.dart';
import '../widgets/schedule_change_review.dart';
import 'admin_schedule_view.dart';
import 'staff_schedule_view.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.user,
    required this.onSignOut,
    this.signingOut = false,
    this.authError,
    this.controller,
    this.repository,
  });
  final AppUser user;
  final Future<void> Function() onSignOut;
  final bool signingOut;
  final String? authError;
  final ScheduleController? controller;
  final ScheduleRepository? repository;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late final ScheduleController c =
      widget.controller ??
      ScheduleController.remote(
        user: widget.user,
        repository: widget.repository!,
      );

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: c.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '송영 날짜 선택',
    );
    if (date != null && mounted) c.selectDate(date);
  }

  Future<void> _confirm() async {
    final snapshot = c.draft;
    final baseline = c.confirmed;
    final catalog = c.catalog;
    final changes = ScheduleChanges.compare(baseline, snapshot, catalog);
    final absenceRevision = c.absenceRevisionKey;
    final approved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(
          '${dateKey(snapshot.date)} (${ScheduleSelectionPolicy.weekday(snapshot.date)}) · ${snapshot.period.label}\n전체 직원 일정 검토',
        ),
        content: SizedBox(
          width: 560,
          height: 380,
          child: ScheduleChangeReview(
            catalog: catalog,
            snapshot: snapshot,
            baseline: baseline,
            changes: changes,
            remote: c.isRemote,
            warnings: c.planningWarnings,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 수정'),
          ),
          FilledButton(
            key: const Key('approve-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(c.isRemote ? 'Firestore에 확정 저장' : '가상 일정 확정'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    if (c.loading ||
        c.saving ||
        c.conflict ||
        c.availabilityLoading ||
        c.availabilityError != null ||
        c.absenceSaving ||
        absenceRevision != c.absenceRevisionKey ||
        c.dataError != null ||
        !identical(snapshot, c.draft) ||
        !identical(baseline, c.confirmed)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('검토 중 일정이 바뀌었거나 조회 중입니다. 최신 내용으로 다시 검토해 주세요.'),
        ),
      );
      return;
    }
    final saved = await c.publish();
    if (!mounted || !saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          c.isRemote ? '전체 직원 일정을 Firestore에 저장했습니다.' : '로컬 테스트 일정을 확정했습니다.',
        ),
      ),
    );
  }

  void _showValidation() {
    final errors = c.validationErrors;
    final warnings = c.planningWarnings;
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('전체 직원 일정 검증'),
        content: SizedBox(
          width: 540,
          height: 320,
          child: ListView(
            children: [
              Text(
                errors.isEmpty
                    ? '일정 충돌·중복 배정·차량 정원 검증 통과'
                    : '아래 오류를 해결한 뒤 확정해 주세요.',
              ),
              for (final error in errors)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (warnings.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('예상 시각 미입력 안내 (확정 가능)'),
                ),
              for (final warning in warnings) Text(warning),
              const SizedBox(height: 16),
              const Text(
                '시연 기준: 같은 시간대 코스는 동시에 운행하는 것으로 검증합니다. 정원은 이용자 수 기준입니다.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _reload() async {
    final approved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('최신 일정 다시 불러오기'),
        content: const Text('현재 선택한 날짜·시간대의 미확정 편집 내용을 폐기하고 서버 최신본을 불러옵니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('최신본 불러오기'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) await c.reloadDiscardingDraft();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (c.loading ||
          c.dataError != null ||
          c.availabilityLoading ||
          c.availabilityError != null) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('다정 송영 관리'),
            actions: [
              TextButton(
                key: const Key('logout'),
                onPressed: widget.signingOut ? null : widget.onSignOut,
                child: const Text('로그아웃'),
              ),
            ],
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: c.loading || c.availabilityLoading
                  ? const CircularProgressIndicator(
                      semanticsLabel: 'Firestore 일정 조회 중',
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c.dataError ?? c.availabilityError!),
                        TextButton(
                          onPressed: c.retryLoad,
                          child: const Text('다시 불러오기'),
                        ),
                      ],
                    ),
            ),
          ),
        );
      }
      final admin = c.role == UserRole.admin;
      final errors = admin ? c.validationErrors : <String>[];
      return Scaffold(
        appBar: AppBar(
          title: const Text('다정 송영 관리'),
          actions: [
            TextButton.icon(
              key: const Key('logout'),
              onPressed: widget.signingOut ? null : widget.onSignOut,
              icon: const Icon(Icons.logout),
              label: Text(widget.signingOut ? '로그아웃 중' : '로그아웃'),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        admin ? '관리자 화면' : '직원 화면',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        c.isRemote
                            ? '가상 데이터 · Firestore 확정 일정 공유'
                            : '가상 데이터 · 로컬 테스트',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (c.reassignmentNeeded || c.confirmedReassignmentNeeded)
                        Text(
                          c.confirmedReassignmentNeeded
                              ? '기존 확정본에 결근 직원의 코스가 있습니다. 재배정 필요 · 새 확정 전에는 정상 운행 일정이 아닙니다.'
                              : '결근 직원의 코스가 남아 있습니다. 재배정이 필요합니다.',
                          key: const Key('staff-absence-warning'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (c.absenceSaving) const Text('결근 상태 저장 중…'),
                      if (c.absenceError != null)
                        Text(
                          c.absenceError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (widget.authError != null)
                        Text(
                          widget.authError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      if (c.saveError != null || c.conflict)
                        Text(
                          c.saveError ?? '다른 관리자가 변경했습니다. 최신본을 확인해 주세요.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (c.conflict || c.saveError != null)
                        TextButton(
                          key: const Key('reload-schedule'),
                          onPressed: c.busy ? null : _reload,
                          child: const Text('편집 내용 폐기 후 최신본 불러오기'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '이전 날짜',
                        onPressed: () => c.selectDate(
                          DateTime(
                            c.selectedDate.year,
                            c.selectedDate.month,
                            c.selectedDate.day - 1,
                          ),
                        ),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      SizedBox(
                        width: MediaQuery.sizeOf(context).width < 500
                            ? 176
                            : null,
                        child: OutlinedButton.icon(
                          key: const Key('select-date'),
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            c.selectedScheduleLabel,
                            key: const Key('selected-schedule-label'),
                            textAlign: TextAlign.center,
                            style: MediaQuery.sizeOf(context).width < 500
                                ? const TextStyle(fontSize: 12)
                                : null,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '다음 날짜',
                        onPressed: () => c.selectDate(
                          DateTime(
                            c.selectedDate.year,
                            c.selectedDate.month,
                            c.selectedDate.day + 1,
                          ),
                        ),
                        icon: const Icon(Icons.chevron_right),
                      ),
                      TextButton(
                        key: const Key('current-schedule'),
                        onPressed: c.selectCurrentSchedule,
                        child: const Text('현재 일정'),
                      ),
                      SegmentedButton<TransportPeriod>(
                        segments: const [
                          ButtonSegment(
                            value: TransportPeriod.morning,
                            label: Text('오전'),
                          ),
                          ButtonSegment(
                            value: TransportPeriod.afternoon,
                            label: Text('오후'),
                          ),
                        ],
                        selected: {c.period},
                        onSelectionChanged: (values) =>
                            c.selectPeriod(values.first),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: admin
                      ? AbsorbPointer(
                          absorbing: c.busy,
                          child: AdminScheduleView(controller: c),
                        )
                      : StaffScheduleView(controller: c),
                ),
                if (admin)
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: _reviewBar(errors),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _reviewBar(List<String> errors) => LayoutBuilder(
    builder: (context, size) {
      final status = Text(
        c.confirmedReassignmentNeeded
            ? '확정 이력 v${c.confirmed!.version} · 재배정 필요'
            : c.confirmed == null
            ? '작성 중 · 아직 확정하지 않은 일정입니다.'
            : c.hasPendingChanges
            ? '수정 중 · 확정본 v${c.confirmed!.version} 유지'
            : '확정 완료 · v${c.confirmed!.version}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      final validationLabel = errors.isEmpty
          ? '전체 검증 통과'
          : '충돌·배정 오류 ${errors.length}건';
      final icon = Icon(
        errors.isEmpty ? Icons.check_circle_outline : Icons.warning_amber,
        color: errors.isEmpty ? Colors.teal : Colors.red,
      );
      final confirm = FilledButton.icon(
        key: const Key('confirm-schedule'),
        onPressed:
            !c.busy &&
                !c.conflict &&
                errors.isEmpty &&
                (c.confirmed == null || c.hasPendingChanges)
            ? _confirm
            : null,
        icon: const Icon(Icons.check),
        label: Text(c.saving ? 'Firestore 저장 중…' : '전체 직원 변경 검토·확정'),
      );
      if (size.maxWidth < 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            status,
            Row(
              children: [
                IconButton(
                  key: const Key('validation-results'),
                  tooltip: validationLabel,
                  onPressed: _showValidation,
                  icon: Badge(
                    isLabelVisible: errors.isNotEmpty,
                    label: Text('${errors.length}'),
                    child: icon,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: confirm),
              ],
            ),
          ],
        );
      }
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          status,
          TextButton.icon(
            key: const Key('validation-results'),
            onPressed: _showValidation,
            icon: icon,
            label: Text(validationLabel),
          ),
          confirm,
        ],
      );
    },
  );
}
