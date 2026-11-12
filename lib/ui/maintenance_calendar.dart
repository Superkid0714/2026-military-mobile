import 'package:flutter/material.dart';

import 'components.dart';

class MaintenanceCalendar extends StatelessWidget {
  const MaintenanceCalendar({
    required this.month,
    required this.counts,
    required this.selected,
    required this.onMonthChanged,
    required this.onSelected,
    super.key,
  });

  final DateTime month;
  final Map<int, int> counts;
  final int? selected;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final offset = month.weekday % 7;
    final cells = ((offset + days + 6) ~/ 7) * 7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '이전 달',
              onPressed: () =>
                  onMonthChanged(DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${month.year}년 ${month.month}월',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: '다음 달',
              onPressed: () =>
                  onMonthChanged(DateTime(month.year, month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final label in ['일', '월', '화', '수', '목', '금', '토'])
              Expanded(
                child: Center(
                  child: Text(label, style: const TextStyle(color: muted)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: MediaQuery.textScalerOf(context).scale(12) > 17
                ? 84
                : 68,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemBuilder: (context, index) {
            final day = index - offset + 1;
            if (day < 1 || day > days) return const SizedBox.shrink();
            final count = counts[day] ?? 0;
            final active = selected == day;
            return Material(
              color: active
                  ? brandFill
                  : count > 0
                  ? brandTint
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelected(day),
                child: Semantics(
                  selected: active,
                  label: '$day일, 일정 $count건',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          color: active
                              ? ink
                              : index % 7 == 0
                              ? const Color(0xFFB54747)
                              : ink,
                          fontWeight: count > 0 || active
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      if (count > 0)
                        Text(
                          '$count건',
                          style: TextStyle(
                            color: active ? ink : green,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
