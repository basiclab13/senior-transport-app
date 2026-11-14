import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/attendance_record.dart';
import '../models/transport.dart';
import '../services/attendance_repository.dart';
import '../utils/display_wording.dart';

class AdminWorkPhotos extends StatefulWidget {
  const AdminWorkPhotos({
    super.key,
    required this.repository,
    required this.user,
    required this.staffId,
    required this.date,
    required this.period,
    required this.routeNames,
  });
  final AttendanceRepository repository;
  final AppUser user;
  final String staffId, date;
  final TransportPeriod period;
  final Map<String, String> routeNames;
  @override
  State<AdminWorkPhotos> createState() => _AdminWorkPhotosState();
}

class _AdminWorkPhotosState extends State<AdminWorkPhotos>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late Future<List<AttendanceSummary>> _records;
  final _images = <String, Future<Uint8List>>{};
  final _legacyBytes = <String, Uint8List>{};
  final _expanded = <String>{};
  final _large = <String>{};
  var _generation = 0;
  String _id(AttendanceSummary s) =>
      '${s.recordId}/${s.registeredAt.toUtc().toIso8601String()}';
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant AdminWorkPhotos old) {
    super.didUpdateWidget(old);
    if (widget.repository != old.repository ||
        widget.staffId != old.staffId ||
        widget.date != old.date ||
        widget.period != old.period ||
        widget.user.uid != old.user.uid ||
        widget.user.role != old.user.role) {
      _images.clear();
      _legacyBytes.clear();
      _expanded.clear();
      _large.clear();
      _reload();
    }
  }

  void _reload() {
    final generation = ++_generation;
    _records = widget.user.role == UserRole.admin && widget.repository.enabled
        ? _load(generation)
        : Future.value([]);
    // A refresh may fail before the next frame attaches FutureBuilder. Keep the
    // original future (and its error state) without an unhandled async error.
    _records.ignore();
  }

  Future<List<AttendanceSummary>> _load(int generation) async {
    final repository = widget.repository;
    if (repository is AttendanceSummaryRepository) {
      return repository.summaries(widget.staffId, widget.date, widget.period);
    }
    // Legacy Emulator Blob documents already contain their images. No second fetch.
    var stream = repository.watch(widget.staffId, widget.date, widget.period);
    if (repository is FirebaseAttendanceRepository) {
      // Its initial cache-only snapshot is a pending StateError, not proof that
      // records are absent. Wait for the verified server snapshot, with a bound.
      stream = stream.handleError((Object _) {}, test: (e) => e is StateError);
    }
    final records = await stream.timeout(const Duration(seconds: 15)).first;
    if (!mounted || generation != _generation) {
      throw StateError('조회 대상이 변경되었습니다.');
    }
    final summaries = <AttendanceSummary>[];
    for (final r in records) {
      final summary = AttendanceSummary(
        recordId: AttendanceRecord.recordId(
          r.date,
          r.period,
          r.routeId,
          r.kind,
        ),
        staffId: r.staffId,
        date: r.date,
        period: r.period,
        routeId: r.routeId,
        kind: r.kind,
        registeredAt: r.registeredAt,
      );
      if (r.staffId != widget.staffId ||
          r.date != widget.date ||
          r.period != widget.period) {
        throw StateError('사진 조회 대상을 확인해 주세요.');
      }
      _legacyBytes[_id(summary)] = r.photo;
      summaries.add(summary);
    }
    return summaries;
  }

  Future<Uint8List> _photo(AttendanceSummary summary) =>
      _images.putIfAbsent(_id(summary), () {
        final repository = widget.repository;
        if (repository is AttendanceSummaryRepository) {
          return repository.photo(summary);
        }
        return Future.value(_legacyBytes[_id(summary)]!);
      });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.user.role != UserRole.admin || !widget.repository.enabled) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '업무 시작·종료 기록',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  key: const Key('refresh-admin-photos'),
                  tooltip: '사진 기록 새로고침',
                  onPressed: () => setState(_reload),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text('등록 시각 · 한국 시간', style: TextStyle(fontSize: 12)),
            FutureBuilder<List<AttendanceSummary>>(
              future: _records,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('사진 기록을 확인하고 있습니다.'),
                  );
                }
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '사진 기록 조회 실패 · 미등록 여부를 알 수 없습니다. 연결과 계정을 확인한 뒤 새로고침해 주세요.',
                      key: Key('admin-photo-record-error'),
                      style: TextStyle(color: Colors.red),
                    ),
                  );
                }
                final records = snapshot.data!;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final start = _kind(WorkPhotoKind.start, records),
                        end = _kind(WorkPhotoKind.end, records);
                    return constraints.maxWidth >= 560
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: start),
                              const SizedBox(width: 12),
                              Expanded(child: end),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [start, const SizedBox(height: 8), end],
                          );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _kind(WorkPhotoKind kind, List<AttendanceSummary> records) {
    final selected = records.where((s) => s.kind == kind).toList()
      ..sort((a, b) => a.registeredAt.compareTo(b.registeredAt));
    return DecoratedBox(
      key: ValueKey('admin-photo-${kind.name}'),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    kind.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(
                  selected.isEmpty
                      ? Icons.radio_button_unchecked
                      : Icons.check_circle_outline,
                  size: 16,
                  color: selected.isEmpty
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Colors.teal,
                ),
                const SizedBox(width: 4),
                Text(
                  selected.isEmpty ? '미등록' : '등록됨',
                  style: TextStyle(
                    fontSize: 12,
                    color: selected.isEmpty
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Colors.teal,
                  ),
                ),
              ],
            ),
            for (final summary in selected) ...[
              const SizedBox(height: 8),
              Text(
                displayName(widget.routeNames[summary.routeId] ?? '이전 코스'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text('등록 · ${summary.koreaTime}'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('show-photo-${summary.recordId}'),
                  onPressed: () => setState(() {
                    if (!_expanded.remove(_id(summary))) {
                      _expanded.add(_id(summary));
                    }
                  }),
                  icon: Icon(
                    _expanded.contains(_id(summary))
                        ? Icons.expand_less
                        : Icons.photo_outlined,
                  ),
                  label: Text(
                    _expanded.contains(_id(summary)) ? '사진 접기' : '사진 보기',
                  ),
                ),
              ),
              if (_expanded.contains(_id(summary)))
                FutureBuilder<Uint8List>(
                  future: _photo(summary),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('등록 기록은 있지만 사진을 불러오지 못했습니다.'),
                          TextButton(
                            onPressed: () => setState(() {
                              _images.remove(_id(summary));
                            }),
                            child: const Text('사진 다시 불러오기'),
                          ),
                        ],
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('사진을 불러오고 있습니다.'),
                      );
                    }
                    final large = _large.contains(_id(summary));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.memory(
                          snapshot.data!,
                          height: large ? 300 : 100,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Text('등록된 사진을 표시할 수 없습니다.'),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: ValueKey('enlarge-photo-${summary.recordId}'),
                            onPressed: () => setState(() {
                              if (!_large.remove(_id(summary))) {
                                _large.add(_id(summary));
                              }
                            }),
                            icon: Icon(large ? Icons.zoom_out : Icons.zoom_in),
                            label: Text(large ? '작게 보기' : '크게 보기'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
