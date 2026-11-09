enum FrontPart {
  hood('보닛', '후드'),
  leftLamp('왼쪽 전조등', '전조등'),
  grille('그릴', '라디에이터 그릴'),
  rightLamp('오른쪽 전조등', '전조등'),
  bumper('앞범퍼', '프런트 범퍼'),
  battery('배터리', '배터리'),
  coolantTank('냉각수통', '냉각수 보조탱크'),
  airCleaner('에어클리너', '에어클리너'),
  oilDipstick('오일 게이지', '엔진 오일 레벨 게이지');

  const FrontPart(this.label, this.searchTerm);
  final String label, searchTerm;

  int get number => FrontInspectionArea.engineBay.parts.contains(this)
      ? FrontInspectionArea.engineBay.parts.indexOf(this) + 1
      : FrontInspectionArea.exterior.parts.indexOf(this) + 1;
}

enum FrontInspectionArea {
  exterior('전면 외관', '전면', '전면 사진 찍기', [
    FrontPart.hood,
    FrontPart.leftLamp,
    FrontPart.grille,
    FrontPart.rightLamp,
    FrontPart.bumper,
  ]),
  engineBay('엔진룸', '엔진룸', '엔진룸 사진 찍기', [
    FrontPart.battery,
    FrontPart.coolantTank,
    FrontPart.airCleaner,
    FrontPart.oilDipstick,
  ]);

  const FrontInspectionArea(
    this.label,
    this.recordArea,
    this.captureLabel,
    this.parts,
  );

  final String label, recordArea, captureLabel;
  final List<FrontPart> parts;
}

enum FrontCheck {
  checked('점검 완료'),
  review('추가 확인'),
  hidden('사진에서 확인 어려움');

  const FrontCheck(this.label);
  final String label;
}

/// Coordinates are fractions of the displayed photo, measured from its top left.
class FrontObservation {
  const FrontObservation(this.status, {this.x, this.y});

  final FrontCheck status;
  final double? x, y;

  Map<String, Object?> toJson() => {
    'status': status.name,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
  };

  static Map<FrontPart, FrontObservation> decode(Object? raw) {
    if (raw == null) return const {};
    if (raw is! Map || raw.length > FrontPart.values.length) {
      throw const FormatException('전면 점검 부위가 올바르지 않습니다.');
    }
    final observations = <FrontPart, FrontObservation>{};
    for (final entry in raw.entries) {
      final part = FrontPart.values
          .where((p) => p.name == entry.key)
          .firstOrNull;
      final value = entry.value;
      if (part == null || value is! Map) {
        throw const FormatException('전면 점검 부위가 올바르지 않습니다.');
      }
      final status = FrontCheck.values
          .where((s) => s.name == value['status'])
          .firstOrNull;
      final x = value['x'], y = value['y'];
      if (status == null ||
          (status == FrontCheck.hidden
              ? x != null || y != null
              : !_coordinate(x) || !_coordinate(y))) {
        throw const FormatException('사진에 표시한 위치가 올바르지 않습니다.');
      }
      observations[part] = FrontObservation(
        status,
        x: (x as num?)?.toDouble(),
        y: (y as num?)?.toDouble(),
      );
    }
    return Map.unmodifiable(observations);
  }

  static bool _coordinate(Object? value) =>
      value is num && value.isFinite && value >= 0 && value <= 1;
}

class FrontPartProposal {
  const FrontPartProposal(this.left, this.top, this.right, this.bottom);

  static const modelId = 'rexton-front-parts-v2';
  final double left, top, right, bottom;

  double get x => (left + right) / 2;
  double get y => (top + bottom) / 2;

  static Map<FrontPart, FrontPartProposal> decode(Map<String, Object?> output) {
    final rows = output['proposals'];
    if (output['modelId'] != modelId ||
        rows is! List ||
        rows.length > FrontInspectionArea.exterior.parts.length) {
      throw const FormatException('부위 후보를 확인할 수 없습니다.');
    }
    final proposals = <FrontPart, FrontPartProposal>{};
    for (final row in rows) {
      if (row is! Map) throw const FormatException('잘못된 부위 후보입니다.');
      final part = FrontInspectionArea.exterior.parts
          .where((p) => p.name == row['part'])
          .firstOrNull;
      final box = row['box'];
      if (part == null ||
          proposals.containsKey(part) ||
          box is! List ||
          box.length != 4 ||
          !box.every(FrontObservation._coordinate)) {
        throw const FormatException('잘못된 부위 후보입니다.');
      }
      final [left, top, right, bottom] = box
          .cast<num>()
          .map((v) => v.toDouble())
          .toList();
      if (left >= right || top >= bottom) {
        throw const FormatException('잘못된 부위 위치입니다.');
      }
      proposals[part] = FrontPartProposal(left, top, right, bottom);
    }
    return Map.unmodifiable(proposals);
  }
}
