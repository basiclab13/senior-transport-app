import 'package:flutter/material.dart';

import '../utils/display_wording.dart';

import '../models/app_user.dart';
import '../services/catalog_preview_repository.dart';
import '../services/schedule_controller.dart';
import 'schedule_screen.dart';

class CatalogPreviewScreen extends StatefulWidget {
  const CatalogPreviewScreen({
    super.key,
    required this.user,
    required this.source,
    required this.onSignOut,
  });
  final AppUser user;
  final CatalogPreviewSource source;
  final Future<void> Function() onSignOut;
  @override
  State<CatalogPreviewScreen> createState() => _CatalogPreviewScreenState();
}

class _CatalogPreviewScreenState extends State<CatalogPreviewScreen> {
  late Future<CatalogPreviewData> _future = _load();
  ScheduleController? _controller;
  String _scenario = 'unchanged';
  Future<CatalogPreviewData> _load() async {
    if (widget.user.role != UserRole.admin) throw StateError('관리자 전용 테스트입니다.');
    return widget.source.load(widget.user);
  }

  ScheduleController _create(CatalogPreviewData data) =>
      ScheduleController.remote(
        user: widget.user,
        repository: CatalogPreviewRepository(
          data: data,
          source: widget.source,
          user: widget.user,
          scenario: _scenario,
        ),
      );
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _select(CatalogPreviewData data, String? scenario) async {
    if (scenario == null) return;
    final approved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('테스트 상황을 다시 불러올까요?'),
        content: const Text('이 화면의 변경사항을 버립니다. 운영 일정과 결근 기록은 바뀌지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 편집'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('상황 불러오기'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    final date = _controller!.selectedDate;
    final period = _controller!.period;
    _controller!.dispose();
    setState(() {
      _scenario = scenario;
      _controller = _create(data)
        ..selectDate(date)
        ..selectPeriod(period);
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CatalogPreviewData>(
    future: _future,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(title: const Text('AI 테스트')),
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          '테스트 일정을 불러오지 못했습니다.\n다시 시도하거나 관리자에게 문의해 주세요.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _future = _load()),
                        child: const Text('다시 읽기'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        );
      }
      final data = snapshot.data!;
      final c = _controller ??= _create(data);
      return ScheduleScreen(
        key: ObjectKey(c),
        user: widget.user,
        controller: c,
        onSignOut: widget.onSignOut,
        previewControls: ListenableBuilder(
          listenable: c,
          builder: (context, _) => ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height < 700 ? 120 : 260,
            ),
            child: SingleChildScrollView(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).height < 700 ? 8 : 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI 테스트 · 실제 일정과 분리 · 저장되지 않음',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: MediaQuery.sizeOf(context).height < 700
                              ? 13
                              : null,
                        ),
                      ),
                      Text(
                        MediaQuery.sizeOf(context).height < 700
                            ? '담당20 · 예비5 · 이용자80 · 정원4'
                            : '직원 25명(담당 20 · 예비 5) · 이용자 80명 · 차량 20대/정원 4명',
                        style: TextStyle(
                          fontSize: MediaQuery.sizeOf(context).height < 700
                              ? 12
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        key: ValueKey('preview-scenario-$_scenario'),
                        initialValue: _scenario,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '테스트 상황'),
                        items: previewScenarios.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: c.busy || c.suggesting
                            ? null
                            : (value) => _select(data, value),
                      ),
                      ExpansionTile(
                        title: const Text('예비 직원 5명 · 테스트 안내'),
                        tilePadding: EdgeInsets.zero,
                        children: [
                          Wrap(
                            spacing: 8,
                            children: data.catalog.staff
                                .where(
                                  (s) => data.reserveStaffIds.contains(s.id),
                                )
                                .map(
                                  (s) => Chip(label: Text(displayName(s.name))),
                                )
                                .toList(),
                          ),
                          const Text(
                            '이 화면의 변경은 나가면 사라집니다. 실제 일정과 결근 기록은 바뀌지 않습니다.',
                          ),
                        ],
                      ),
                      if (!widget.source.allowsPreviewRequests)
                        const Text('지금은 조회·편집만 가능합니다. AI 추천은 사용할 수 없습니다.'),
                      if (_scenario == 'six-staff-absent')
                        const Text('20코스를 맡을 직원이 부족합니다. 결근 상태를 확인해 주세요.'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
