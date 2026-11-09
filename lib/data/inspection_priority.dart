import 'calendar.dart';
import 'store.dart';

class InspectionPriority {
  const InspectionPriority(this.part, this.order, this.reason);
  final String part, reason;
  // Due rules precede repeat repairs, then model-assisted general inspection.
  // This is an inspection queue, never an automatic replacement decision.
  final int order;
}

extension InspectionPriorities on AppStore {
  List<InspectionPriority> inspectionPriorities(String vehicleId) {
    final result = <InspectionPriority>[];
    final rules = supportLibrary.rules.where((r) => r.vehicleId == vehicleId);
    for (final rule in rules) {
      final state = serviceDistance(rule);
      final due =
          state.remainingKm == 0 ||
          (state.remainingDays != null && state.remainingDays! <= 0);
      result.add(
        InspectionPriority(
          standardPart(rule.part),
          due ? 0 : 3,
          due
              ? '확인된 정비 주기가 도래했습니다. 점검 후 작업 여부를 결정하세요.'
              : state.remainingKm == null && state.remainingDays == null
              ? '기준 확인 필요: ${state.reason ?? state.calendarReason ?? '교환 기준 정보 부족'}'
              : '정비 주기 여유: ${[if (state.remainingKm != null) '${state.remainingKm} km', if (state.remainingDays != null) '${state.remainingDays}일'].join(' / ')} 남음',
        ),
      );
    }
    final today = clock();
    final repeated = <String, int>{};
    for (final record in history(vehicleId)) {
      final date = DateTime.tryParse(record.date);
      if (date == null) continue;
      final days = calendarDaysBetween(today, date);
      if (days < 0 || days >= 90 || record.maintenanceType != '고장수리') {
        continue;
      }
      final part = standardPart(record.part);
      if (part.isNotEmpty) {
        repeated.update(part, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    for (final item in repeated.entries.where((e) => e.value >= 2)) {
      result.add(
        InspectionPriority(
          item.key,
          1,
          '최근 90일 고장수리 ${item.value}회 기록. 재발 원인을 확인하세요.',
        ),
      );
    }
    final v = vehicle(vehicleId);
    if (v.predictionReady) {
      result.add(
        InspectionPriority(
          '차량 종합 점검',
          2,
          'AI 분석 점수 ${v.risk}%. ${v.risk >= v.cautionThreshold ? '추가 점검을 권장합니다.' : '정기 점검을 유지하세요.'}',
        ),
      );
    }
    if (result.isEmpty) {
      result.add(
        const InspectionPriority(
          '점검 기준 확인',
          3,
          '확인된 정비 주기나 반복 수리 근거가 없습니다. 교환 기준과 운용 기록을 입력하세요.',
        ),
      );
    }
    result.sort((a, b) {
      final order = a.order.compareTo(b.order);
      return order != 0 ? order : a.part.compareTo(b.part);
    });
    return result;
  }
}
