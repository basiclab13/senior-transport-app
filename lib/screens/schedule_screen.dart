import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/transport.dart';
import '../services/schedule_controller.dart';
import '../services/schedule_repository.dart';
import '../services/schedule_selection_policy.dart';
import '../models/schedule_changes.dart';
import '../widgets/schedule_change_review.dart';
import '../widgets/ai_schedule_suggestion_dialog.dart';
import '../utils/schedule_wording.dart';
import '../utils/admin_schedule_status.dart';
import 'admin_schedule_view.dart';
import 'staff_schedule_view.dart';
import '../services/catalog_preview_repository.dart';
import 'catalog_preview_screen.dart';
import '../widgets/app_info_button.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.user,
    required this.onSignOut,
    this.signingOut = false,
    this.authError,
    this.controller,
    this.repository,
    this.catalogPreviewSource,
    this.previewControls,
  });
  final AppUser user;
  final Future<void> Function() onSignOut;
  final bool signingOut;
  final String? authError;
  final ScheduleController? controller;
  final ScheduleRepository? repository;
  final CatalogPreviewSource? catalogPreviewSource;
  final Widget? previewControls;

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
    if (c.isCatalogPreview) return;
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
          child: Column(
            children: [
              Expanded(
                child: ScheduleChangeReview(
                  catalog: catalog,
                  snapshot: snapshot,
                  baseline: baseline,
                  changes: changes,
                  remote: c.isRemote,
                  warnings: const <String>[],
                ),
              ),
            ],
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
            child: Text(c.isRemote ? '최종 일정 확정' : '최종 일정 확정'),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('전체 직원 일정을 확정했습니다.')));
  }

  Future<void> _suggest() async {
    try {
      final suggestion = await c.requestAiSuggestion();
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (_) =>
            AiScheduleSuggestionDialog(controller: c, suggestion: suggestion),
      );
      if (approved != true || !mounted) return;
      c.applyAiSuggestion(suggestion);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? easyScheduleMessage(error.message)
                : 'AI 요청을 완료하지 못했습니다. 기존 일정은 유지됩니다.',
          ),
        ),
      );
    }
  }

  void _showValidation() {
    final errors = adminBlockingMessages(c);
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('확정 전 확인'),
        content: SizedBox(
          width: 540,
          height: 320,
          child: ListView(
            children: [
              Text(
                errors.isEmpty ? '확정을 막는 오류가 없습니다.' : '확정 불가 · 아래 오류를 해결해 주세요.',
              ),
              for (final error in errors)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    easyScheduleMessage(error),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Text('직원·차량은 오전과 오후에 각각 한 코스만 맡을 수 있습니다.'),
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
        content: const Text('선택한 일정의 수정 내용을 버리고 저장된 일정을 다시 불러옵니다.'),
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
            title: const Text('송영도우미'),
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
                      semanticsLabel: '송영 일정 확인 중',
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          easyScheduleMessage(
                            c.dataError ?? c.availabilityError!,
                          ),
                        ),
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
      final errors = admin ? adminBlockingMessages(c) : <String>[];
      return Scaffold(
        appBar: AppBar(
          title: Text(
            c.isCatalogPreview
                ? 'AI 테스트'
                : admin
                ? '송영 현황'
                : '내 송영 일정',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18),
          ),
          actions: [
            const AppInfoButton(),
            if (admin && c.supportsAiSuggestions && !c.isCatalogPreview)
              _suggestButton(compact: MediaQuery.sizeOf(context).width < 768),
            if (admin &&
                !c.isCatalogPreview &&
                widget.catalogPreviewSource != null)
              TextButton.icon(
                key: const Key('open-catalog-preview'),
                icon: const Icon(Icons.science_outlined),
                label: const Text('AI 테스트'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CatalogPreviewScreen(
                      user: widget.user,
                      source: widget.catalogPreviewSource!,
                      onSignOut: widget.onSignOut,
                    ),
                  ),
                ),
              ),
            if (MediaQuery.sizeOf(context).width < 600)
              IconButton(
                key: const Key('logout'),
                tooltip: '로그아웃',
                icon: const Icon(Icons.logout),
                onPressed: widget.signingOut ? null : widget.onSignOut,
              )
            else
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
            constraints: BoxConstraints(maxWidth: admin ? 1440 : 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.isCatalogPreview && widget.previewControls != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: widget.previewControls!,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (admin &&
                          (c.reassignmentNeeded ||
                              c.confirmedReassignmentNeeded))
                        Text(
                          c.confirmedReassignmentNeeded
                              ? '공유된 결근 코스가 있습니다. 인계 내용을 확인하고 다시 확정해 주세요.'
                              : '결근 직원의 담당 코스를 다른 직원에게 넘겨주세요.',
                          key: const Key('staff-absence-warning'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (c.absenceSaving) const Text('결근 상태 저장 중…'),
                      if (c.absenceError != null)
                        Text(
                          easyScheduleMessage(c.absenceError!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (widget.authError != null)
                        Text(
                          easyScheduleMessage(widget.authError!),
                          style: const TextStyle(color: Colors.red),
                        ),
                      if (c.saveError != null || c.conflict)
                        Text(
                          easyScheduleMessage(
                            c.saveError ?? '다른 관리자가 변경했습니다. 최신본을 확인해 주세요.',
                          ),
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
                          child: const Text('수정한 내용을 버리고 다시 불러오기'),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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

  Widget _suggestButton({bool compact = false}) {
    final disabled =
        c.suggesting ||
        c.busy ||
        c.loading ||
        c.dataError != null ||
        c.availabilityLoading ||
        c.availabilityError != null ||
        c.conflict;
    final icon = c.suggesting
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.auto_awesome_outlined);
    return compact
        ? IconButton(
            key: const Key('suggest-schedule'),
            tooltip: 'AI 일정 제안',
            onPressed: disabled ? null : _suggest,
            icon: icon,
          )
        : TextButton.icon(
            key: const Key('suggest-schedule'),
            onPressed: disabled ? null : _suggest,
            icon: icon,
            label: Text(c.suggesting ? 'AI 제안 생성 중…' : 'AI 일정 제안'),
          );
  }

  Widget _reviewBar(List<String> errors) => LayoutBuilder(
    builder: (context, size) {
      if (c.isCatalogPreview) {
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('이 화면의 변경은 저장·확정되지 않습니다.'),
            if (c.supportsAiSuggestions) _suggestButton(),
          ],
        );
      }
      final visibleChanges = hasScheduleContentChanges(c);
      final warnings = const <String>[];
      final unchanged =
          c.confirmed != null &&
          !visibleChanges &&
          !c.confirmedReassignmentNeeded &&
          c.saveError == null &&
          errors.isEmpty &&
          !c.busy &&
          !c.conflict;
      if (unchanged) {
        return Row(
          key: const Key('confirmed-no-changes'),
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.teal,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(adminScheduleStatus(c))),
            if (c.hasPendingChanges)
              TextButton.icon(
                key: const Key('confirm-schedule'),
                onPressed: _confirm,
                icon: const Icon(Icons.check),
                label: const Text('일정 확인'),
              ),
            IconButton(
              key: const Key('validation-results'),
              tooltip: warnings.isEmpty ? '검사 결과' : '확인 필요 ${warnings.length}건',
              onPressed: _showValidation,
              icon: Icon(
                warnings.isEmpty
                    ? Icons.fact_check_outlined
                    : Icons.info_outline,
                color: warnings.isEmpty
                    ? null
                    : Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ],
        );
      }
      final status = Text(
        adminScheduleStatus(c),
        key: const Key('admin-schedule-status'),
        style: const TextStyle(fontWeight: FontWeight.w600),
      );
      final validationLabel = errors.isNotEmpty
          ? '확정 불가 ${errors.length}건'
          : warnings.isNotEmpty
          ? '확인 필요 ${warnings.length}건'
          : '검사 결과';
      final icon = Icon(
        errors.isNotEmpty
            ? Icons.error_outline
            : warnings.isNotEmpty
            ? Icons.info_outline
            : Icons.fact_check_outlined,
        color: errors.isNotEmpty
            ? Theme.of(context).colorScheme.error
            : warnings.isNotEmpty
            ? Theme.of(context).colorScheme.tertiary
            : null,
      );
      final VoidCallback? onConfirm =
          !c.busy &&
              !c.conflict &&
              errors.isEmpty &&
              (c.confirmed == null || c.hasPendingChanges)
          ? _confirm
          : null;
      final Widget confirm =
          c.confirmed != null &&
              !visibleChanges &&
              errors.isEmpty &&
              !c.confirmedReassignmentNeeded
          ? TextButton.icon(
              key: const Key('confirm-schedule'),
              onPressed: onConfirm,
              icon: const Icon(Icons.check),
              label: const Text('일정 확인'),
            )
          : FilledButton.icon(
              key: const Key('confirm-schedule'),
              onPressed: onConfirm,
              icon: const Icon(Icons.check),
              label: Text(c.saving ? '일정 확정 중…' : '변경 내용 확인 후 확정'),
            );
      if (size.maxWidth < 768) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: status),
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
              ],
            ),
            confirm,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: status),
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
