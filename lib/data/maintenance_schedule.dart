part of 'store.dart';

class MaintenanceSchedule {
  const MaintenanceSchedule({
    required this.id,
    required this.vehicleId,
    required this.date,
    required this.title,
    this.note = '',
  });

  final String id, vehicleId, date, title, note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicleId': vehicleId,
    'date': date,
    'title': title,
    'note': note,
  };

  static List<MaintenanceSchedule> decode(String raw) {
    final values = jsonDecode(raw);
    if (values is! List || values.length > 10000) {
      throw const FormatException('일정 자료를 확인해 주세요.');
    }
    final ids = <String>{};
    final result = <MaintenanceSchedule>[];
    for (final row in values) {
      if (row is! Map ||
          ![
            'id',
            'vehicleId',
            'date',
            'title',
            'note',
          ].every((key) => row[key] is String)) {
        throw const FormatException('일정 자료를 확인해 주세요.');
      }
      final date = DateTime.tryParse(row['date']);
      if (row['id'].isEmpty ||
          row['id'].length > 120 ||
          !ids.add(row['id']) ||
          row['vehicleId'].isEmpty ||
          row['vehicleId'].length > 120 ||
          date == null ||
          row['date'] != date.toIso8601String().substring(0, 10) ||
          date.year < 2000 ||
          date.year > 2100 ||
          row['title'].trim().isEmpty ||
          row['title'].length > 120 ||
          row['note'].length > 2000) {
        throw const FormatException('날짜와 일정 내용을 확인해 주세요.');
      }
      result.add(
        MaintenanceSchedule(
          id: row['id'],
          vehicleId: row['vehicleId'],
          date: row['date'],
          title: row['title'],
          note: row['note'],
        ),
      );
    }
    return result;
  }
}

extension ScheduleStorage on AppStore {
  Future<void> saveSchedule(MaintenanceSchedule schedule) => _mutate(() async {
    if (!vehicles.any((vehicle) => vehicle.id == schedule.vehicleId)) {
      throw ArgumentError('차량을 다시 선택해 주세요.');
    }
    await _writeSchedules([
      ...schedules.where((item) => item.id != schedule.id),
      schedule,
    ]);
  });

  Future<void> deleteSchedule(String id) => _mutate(
    () => _writeSchedules(schedules.where((item) => item.id != id).toList()),
  );

  Future<void> _writeSchedules(List<MaintenanceSchedule> values) async {
    final raw = jsonEncode(values.map((item) => item.toJson()).toList());
    final checked = MaintenanceSchedule.decode(raw);
    await db!.customStatement(
      'INSERT OR REPLACE INTO app_metadata (key,value) VALUES (?,?)',
      ['maintenance_schedules', raw],
    );
    schedules = checked..sort((a, b) => a.date.compareTo(b.date));
    _notifyChanged();
  }
}
