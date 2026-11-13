import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/attendance_record.dart';
import '../models/transport.dart';
import '../services/attendance_repository.dart';
import '../services/demo_photo_picker.dart';
import '../services/schedule_controller.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    required this.controller,
    required this.staffId,
    required this.staffName,
    required this.date,
    required this.period,
    this.routeId,
    this.photoPicker,
    this.embedded = false,
  });
  final ScheduleController controller;
  final String staffId, staffName;
  final DateTime date;
  final TransportPeriod period;
  final String? routeId;
  final Future<Uint8List?> Function()? photoPicker;

  /// Reuse the same registration flow inside the employee's schedule.
  final bool embedded;
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  ScheduleController get c => widget.controller;
  AttendanceRepository? get repo => c.attendanceRepository;
  late final records = repo?.enabled == true
      ? repo!.watch(widget.staffId, dateKey(widget.date), widget.period)
      : null;
  late final routeNames = {for (final r in c.catalog.baseRoutes) r.id: r.name};
  WorkPhotoKind? busy;
  bool uploading = false;
  String? error;
  bool get staff => c.user.role == UserRole.staff;
  bool get canRegister =>
      staff &&
      c.user.staffId == widget.staffId &&
      widget.routeId != null &&
      !c.loading &&
      c.dataError == null &&
      c.availabilityError == null &&
      !c.availabilityLoading &&
      dateKey(c.selectedDate) == dateKey(widget.date) &&
      c.period == widget.period &&
      !c.confirmedReassignmentNeeded &&
      c.staffRoutes.any((r) => r.baseRouteId == widget.routeId);

  Future<void> register(WorkPhotoKind kind) async {
    final snapshot = c.confirmed;
    final revision = c.absenceRevisionKey;
    setState(() {
      busy = kind;
      error = null;
    });
    try {
      final photo = await (widget.photoPicker ?? pickDemoPhoto)();
      if (photo == null || !mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text('${kind.label} 사진 확인'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.memory(
                  photo,
                  height: 180,
                  errorBuilder: (_, _, _) => const Text('사진을 표시할 수 없습니다.'),
                ),
                const SizedBox(height: 12),
                const Text(
                  '실제 이용자나 개인정보가 없는 시연용 사진만 등록해 주세요. 등록 시각을 기록하며 실제 도착이나 근무 여부를 인증하지는 않습니다.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              key: const Key('confirm-work-photo'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('시연용 사진으로 등록'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      if (!canRegister ||
          !identical(c.confirmed, snapshot) ||
          c.absenceRevisionKey != revision) {
        throw StateError('담당 일정이나 결근 정보가 변경되었습니다. 내 일정을 다시 확인해 주세요.');
      }
      setState(() {
        uploading = true;
      });
      await repo!.register(
        user: c.user,
        date: dateKey(widget.date),
        period: widget.period,
        routeId: widget.routeId!,
        kind: kind,
        photo: photo,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${kind.label} 사진이 등록되었습니다.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is StateError
              ? e.message.toString()
              : '사진을 등록하지 못했습니다. 연결과 담당 일정을 확인한 뒤 다시 시도해 주세요.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = null;
          uploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? _embedded()
      : Scaffold(
          appBar: AppBar(
            title: Text(staff ? '업무 사진 기록' : '${widget.staffName} 업무 사진 기록'),
          ),
          body: records == null
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text('사진 등록은 Emulator 시연 환경에서 사용할 수 있습니다.'),
                    Text(
                      '${widget.staffName} · ${dateKey(widget.date)} · ${widget.period.label}',
                    ),
                    const Text('이 화면에서는 사진이나 업무 시간이 저장되지 않습니다.'),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('내 일정으로 돌아가기'),
                    ),
                  ],
                )
              : ListenableBuilder(
                  listenable: c,
                  builder: (_, _) => StreamBuilder<List<AttendanceRecord>>(
                    stream: records,
                    builder: (context, snapshot) {
                      final entries = snapshot.data ?? [];
                      final verified = snapshot.hasData && !snapshot.hasError;
                      final started = entries.any(
                        (r) =>
                            r.kind == WorkPhotoKind.start &&
                            r.routeId == widget.routeId,
                      );
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              Text(
                                '${widget.staffName} · ${dateKey(widget.date)} · ${widget.period.label}',
                              ),
                              const Text(
                                '시연용 사진 기록 · 표시 시각은 한국 시간의 서버 등록 시각입니다.',
                              ),
                              if (!verified)
                                Text(
                                  snapshot.hasError
                                      ? '사진 기록을 확인할 수 없습니다. 연결과 계정 권한을 확인해 주세요.'
                                      : '사진 기록을 확인하고 있습니다.',
                                ),
                              if (error != null)
                                Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              if (staff && !canRegister)
                                const Text(
                                  '현재 본인에게 확정된 운행 가능한 코스에서만 사진을 등록할 수 있습니다.',
                                ),
                              for (final kind in WorkPhotoKind.values)
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          '${kind.label} 사진',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge,
                                        ),
                                        for (final r in entries.where(
                                          (r) => r.kind == kind,
                                        )) ...[
                                          Text(
                                            '${routeNames[r.routeId] ?? r.routeId} · 등록 ${r.koreaTime}',
                                          ),
                                          Image.memory(
                                            r.photo,
                                            height: 180,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, _, _) =>
                                                const Text('사진을 표시할 수 없습니다.'),
                                          ),
                                        ],
                                        if (!entries.any((r) => r.kind == kind))
                                          const Text('아직 등록된 사진이 없습니다.'),
                                        if (staff)
                                          FilledButton.icon(
                                            key: Key(
                                              'register-work-${kind.name}',
                                            ),
                                            onPressed:
                                                verified &&
                                                    canRegister &&
                                                    busy == null &&
                                                    !entries.any(
                                                      (r) =>
                                                          r.kind == kind &&
                                                          r.routeId ==
                                                              widget.routeId,
                                                    ) &&
                                                    (kind ==
                                                            WorkPhotoKind
                                                                .start ||
                                                        started)
                                                ? () => register(kind)
                                                : null,
                                            icon: busy == kind && uploading
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Icon(
                                                    Icons.camera_alt_outlined,
                                                  ),
                                            label: Text('${kind.label} 사진 등록'),
                                          ),
                                        if (staff &&
                                            kind == WorkPhotoKind.end &&
                                            !started)
                                          const Text('업무 시작 사진을 먼저 등록해 주세요.'),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        );

  Widget _embedded() {
    if (records == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('사진 등록은 Emulator 시연 환경에서 사용할 수 있습니다.'),
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (_, _) => StreamBuilder<List<AttendanceRecord>>(
        stream: records,
        builder: (context, snapshot) {
          final verified = snapshot.hasData && !snapshot.hasError;
          final entries = snapshot.data ?? <AttendanceRecord>[];
          final current = entries
              .where((r) => r.routeId == widget.routeId)
              .toList();
          final started = current.any((r) => r.kind == WorkPhotoKind.start);
          final ended = current.any((r) => r.kind == WorkPhotoKind.end);
          final next = started ? WorkPhotoKind.end : WorkPhotoKind.start;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!verified)
                Text(
                  snapshot.hasError
                      ? '사진 기록을 확인하지 못했습니다. 연결을 확인한 뒤 화면을 새로고침해 주세요.'
                      : '사진 기록을 확인하고 있습니다.',
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              for (final r in current)
                Text(
                  '${r.kind.label} 사진 등록 · ${r.koreaTime.startsWith(r.date) ? r.koreaTime.substring(11) : r.koreaTime}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (staff && canRegister && !ended)
                FilledButton.icon(
                  key: Key('register-work-${next.name}'),
                  onPressed: verified && busy == null
                      ? () => register(next)
                      : null,
                  icon: uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined),
                  label: Text(uploading ? '사진 등록 중…' : '${next.label} 사진 등록'),
                ),
              if (ended) const Text('업무 시작·종료 사진을 모두 등록했습니다.'),
              if (entries.isNotEmpty)
                ExpansionTile(
                  key: const Key('work-photo-history'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('등록한 사진 보기'),
                  children: [
                    for (final r in entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          children: [
                            Text(
                              '${routeNames[r.routeId] ?? r.routeId} · ${r.kind.label} · ${r.koreaTime}',
                            ),
                            Image.memory(
                              r.photo,
                              height: 160,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Text('사진을 표시할 수 없습니다.'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
