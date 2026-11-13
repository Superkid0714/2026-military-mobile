import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

bool recordInPeriod(String date, DateTimeRange? range) {
  if (range == null) return true;
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return false;
  final day = DateTime(parsed.year, parsed.month, parsed.day);
  return !day.isBefore(range.start) && !day.isAfter(range.end);
}

class RecordTabs extends StatelessWidget {
  const RecordTabs({required this.operations, super.key});
  final bool operations;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('정비 기록'),
          selected: !operations,
          onSelected: (_) {
            if (operations) context.go('/records');
          },
        ),
        ChoiceChip(
          label: const Text('운행 기록'),
          selected: operations,
          onSelected: (_) {
            if (!operations) context.go('/operations');
          },
        ),
      ],
    ),
  );
}

class RecordPeriodFilter extends StatelessWidget {
  const RecordPeriodFilter({
    required this.value,
    required this.now,
    required this.onChanged,
    super.key,
  });
  final DateTimeRange? value;
  final DateTime now;
  final ValueChanged<DateTimeRange?> onChanged;
  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final month = DateTimeRange(
      start: DateTime(now.year, now.month),
      end: today,
    );
    final quarter = DateTimeRange(
      start: DateTime(now.year, now.month - 2),
      end: today,
    );
    String date(DateTime d) =>
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('조회 기간', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('전체 기간'),
              selected: value == null,
              onSelected: (_) => onChanged(null),
            ),
            ChoiceChip(
              label: const Text('이번 달'),
              selected: value == month,
              onSelected: (_) => onChanged(month),
            ),
            ChoiceChip(
              label: const Text('최근 3개월'),
              selected: value == quarter,
              onSelected: (_) => onChanged(quarter),
            ),
            OutlinedButton.icon(
              key: const ValueKey('custom-record-period'),
              icon: const Icon(Icons.date_range_outlined),
              label: const Text('직접 선택'),
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(1950),
                  lastDate: DateTime(2100, 12, 31),
                  initialDateRange: value,
                  currentDate: today,
                  helpText: '조회 기간 선택',
                  saveText: '적용',
                );
                if (range != null) onChanged(range);
              },
            ),
          ],
        ),
        if (value != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${date(value!.start)} ~ ${date(value!.end)} · 시작일·종료일 포함',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
