part of 'store.dart';

enum FieldWorkKind { parts, feedback }

class FieldWork {
  const FieldWork({
    required this.id,
    required this.vehicleId,
    required this.kind,
    required this.part,
    required this.note,
    required this.created,
    this.partNumber = '',
    this.quantity = 1,
    this.closed = false,
  });
  final String id, vehicleId, part, note, created, partNumber;
  final FieldWorkKind kind;
  final int quantity;
  final bool closed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicleId': vehicleId,
    'kind': kind.name,
    'part': part,
    'note': note,
    'created': created,
    'partNumber': partNumber,
    'quantity': quantity,
    'closed': closed,
  };

  static List<FieldWork> decode(String raw) {
    final rows = jsonDecode(raw);
    if (rows is! List || rows.length > 10000) {
      throw const FormatException('현장 요청 자료를 확인해 주세요.');
    }
    final ids = <String>{};
    return rows.map((row) {
      if (row is! Map ||
          ![
            'id',
            'vehicleId',
            'kind',
            'part',
            'note',
            'created',
            'partNumber',
          ].every((key) => row[key] is String) ||
          row['quantity'] is! int ||
          row['closed'] is! bool) {
        throw const FormatException('현장 요청 자료를 확인해 주세요.');
      }
      final kind = FieldWorkKind.values
          .where((kind) => kind.name == row['kind'])
          .firstOrNull;
      final created = DateTime.tryParse(row['created']);
      if (kind == null ||
          row['id'].isEmpty ||
          row['id'].length > 120 ||
          !ids.add(row['id']) ||
          row['vehicleId'].isEmpty ||
          row['vehicleId'].length > 120 ||
          row['part'].trim().isEmpty ||
          row['part'].length > 120 ||
          row['note'].trim().isEmpty ||
          row['note'].length > 2000 ||
          row['partNumber'].length > 120 ||
          row['quantity'] < 1 ||
          row['quantity'] > 999 ||
          row['created'].length > 40 ||
          created == null ||
          row['created'].length < 10 ||
          row['created'].substring(0, 10) !=
              created.toIso8601String().substring(0, 10)) {
        throw const FormatException('차량과 요청 내용을 확인해 주세요.');
      }
      return FieldWork(
        id: row['id'],
        vehicleId: row['vehicleId'],
        kind: kind,
        part: row['part'],
        note: row['note'],
        created: row['created'],
        partNumber: row['partNumber'],
        quantity: row['quantity'],
        closed: row['closed'],
      );
    }).toList();
  }
}

extension FieldWorkStorage on AppStore {
  Future<void> saveFieldWork(FieldWork item) => _mutate(() async {
    if (!vehicles.any((vehicle) => vehicle.id == item.vehicleId)) {
      throw ArgumentError('차량을 다시 선택해 주세요.');
    }
    final values = [...fieldWork.where((row) => row.id != item.id), item];
    await _writeFieldWork(values);
  });

  Future<void> deleteFieldWork(String id) => _mutate(
    () => _writeFieldWork(fieldWork.where((row) => row.id != id).toList()),
  );

  Future<void> _writeFieldWork(List<FieldWork> values) async {
    final raw = jsonEncode(values.map((row) => row.toJson()).toList());
    final checked = FieldWork.decode(raw);
    await db!.customStatement(
      'INSERT OR REPLACE INTO app_metadata (key,value) VALUES (?,?)',
      ['field_work', raw],
    );
    fieldWork = checked..sort((a, b) => b.created.compareTo(a.created));
    _notifyChanged();
  }

  Future<void> closeFieldWork(FieldWork item, bool closed) => saveFieldWork(
    FieldWork(
      id: item.id,
      vehicleId: item.vehicleId,
      kind: item.kind,
      part: item.part,
      note: item.note,
      created: item.created,
      partNumber: item.partNumber,
      quantity: item.quantity,
      closed: closed,
    ),
  );
}
