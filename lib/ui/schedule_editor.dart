import 'package:flutter/material.dart';

import '../data/store.dart';
import 'components.dart';

class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({
    required this.store,
    required this.date,
    this.vehicleId,
    this.schedule,
    super.key,
  });

  final AppStore store;
  final DateTime date;
  final String? vehicleId;
  final MaintenanceSchedule? schedule;

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.schedule?.title);
  late final note = TextEditingController(text: widget.schedule?.note);
  late DateTime date = widget.schedule == null
      ? widget.date
      : DateTime.parse(widget.schedule!.date);
  late String? vehicle =
      widget.schedule?.vehicleId ??
      widget.vehicleId ??
      widget.store.dashboardVehicles.firstOrNull?.id;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate() || vehicle == null) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.saveSchedule(
        MaintenanceSchedule(
          id: widget.schedule?.id ?? widget.store.newId('SCHEDULE'),
          vehicleId: vehicle!,
          date: date.toIso8601String().substring(0, 10),
          title: title.text.trim(),
          note: note.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context, date);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '저장하지 못했습니다. 다시 시도해 주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.schedule == null ? '일정 추가' : '일정 수정'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: vehicle,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '차량'),
                items: [
                  for (final item in widget.store.vehicles)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        '${vehicleLabel(item.id)} · ${modelLabel(item.model)}',
                      ),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => vehicle = value),
                validator: (value) => value == null ? '차량을 선택해 주세요.' : null,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(day(date)),
                onPressed: saving
                    ? null
                    : () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100, 12, 31),
                        );
                        if (picked != null && mounted) {
                          setState(() => date = picked);
                        }
                      },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: title,
                enabled: !saving,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: '정비 내용',
                  hintText: '엔진오일 교환, 타이어 점검',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '정비 내용을 입력해 주세요.'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: note,
                enabled: !saving,
                maxLength: 2000,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '메모'),
              ),
              if (error != null) Text(error!),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? '저장 중…' : '저장'),
      ),
    ],
  );
}
