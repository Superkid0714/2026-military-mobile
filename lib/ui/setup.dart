import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/store.dart';
import 'components.dart';
import 'support.dart' show parseKm;

class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final vehicles = store.registeredVehicles;

    return ListView(
      children: [
        const PageTitle('차량 등록', ''),
        FilledButton.icon(
          onPressed: () async {
            final id = await showDialog<String>(
              context: context,
              builder: (_) => VehicleRegistrationDialog(store: store),
            );
            if (id == null || !context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${vehicleLabel(id)} 차량을 등록했어요.')),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('새 차량 등록'),
        ),
        const SizedBox(height: 16),
        Panel(
          title: '등록한 차량',
          child: vehicles.isEmpty
              ? const Text('아직 등록한 차량이 없습니다.')
              : Column(
                  children: [
                    for (final vehicle in vehicles)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.local_shipping_outlined),
                        title: Text(vehicleLabel(vehicle.id)),
                        subtitle: Text(
                          '${modelLabel(vehicle.model)} · ${vehicle.year}년 · '
                          '${number(vehicle.distance)} km',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/vehicles/${vehicle.id}'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class VehicleRegistrationDialog extends StatefulWidget {
  const VehicleRegistrationDialog({required this.store, super.key});
  final AppStore store;
  @override
  State<VehicleRegistrationDialog> createState() => _VehicleRegistrationState();
}

class _VehicleRegistrationState extends State<VehicleRegistrationDialog> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in [
      '차량번호',
      '차종',
      '출고연도',
      '누적 주행거리(km)',
      '누적 주행시간(H)',
      '누적 유류 사용량(L)',
    ])
      key: TextEditingController(),
  };
  static const examples = {
    '차량번호': '예: 차량-001',
    '차종': '예: 렉스턴 스포츠',
    '출고연도': '예: 2022',
    '누적 주행거리(km)': '예: 20,000',
    '누적 주행시간(H)': '예: 500',
    '누적 유류 사용량(L)': '예: 1,000',
  };
  String? error;
  bool saving = false;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('새 차량 등록'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '차량 기본 정보',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                for (final e in fields.entries) ...[
                  if (e.key == '누적 주행거리(km)') ...[
                    const SizedBox(height: 8),
                    const Text(
                      '현재 누적 계기',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text('현재 기록을 입력하세요. 새 차량의 계기가 0이면 0을 입력하세요.'),
                    const SizedBox(height: 10),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      key: ValueKey('register-${e.key}'),
                      controller: e.value,
                      enabled: !saving,
                      textInputAction: e.key == fields.keys.last
                          ? TextInputAction.done
                          : TextInputAction.next,
                      keyboardType: e.key == '차량번호' || e.key == '차종'
                          ? TextInputType.text
                          : TextInputType.number,
                      decoration: InputDecoration(
                        labelText: e.key,
                        hintText: examples[e.key],
                        errorMaxLines: 3,
                        helperText: e.key == '차량번호'
                            ? '한글·영문·숫자·밑줄·하이픈, 40자 이내'
                            : null,
                      ),
                      validator: (raw) {
                        final value = raw?.trim() ?? '';
                        if (value.isEmpty) return '필수 입력 항목입니다.';
                        if (e.key == '차량번호') {
                          if (!RegExp(r'^[A-Za-z0-9가-힣_-]{1,40}$')
                                  .hasMatch(value) ||
                              value.startsWith('MOCK-')) {
                            return '차량번호 형식을 확인해 주세요. MOCK-는 분석용 차량 전용입니다.';
                          }
                          if (widget.store.vehicles.any((v) => v.id == value)) {
                            return '이미 등록된 차량번호입니다.';
                          }
                        } else if (e.key == '차종') {
                          if (value.length > 300) {
                            return '차종은 300자 이내로 입력해 주세요.';
                          }
                        } else {
                          final n = parseKm(value);
                          if (n == null || n < 0 || n > 1000000000000) {
                            return '0 이상의 누적값을 입력해 주세요. 쉼표도 사용할 수 있습니다.';
                          }
                          if (e.key == '출고연도' &&
                              (n < 1950 || n > widget.store.clock().year)) {
                            return '출고연도를 확인해 주세요.';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ],
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
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
          onPressed: saving
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  setState(() => saving = true);
                  try {
                    final v = Vehicle(
                      id: fields['차량번호']!.text.trim(),
                      model: fields['차종']!.text.trim(),
                      year: parseKm(fields['출고연도']!.text)!,
                      distance: parseKm(fields['누적 주행거리(km)']!.text)!,
                      hours: parseKm(fields['누적 주행시간(H)']!.text)!,
                      fuel: parseKm(fields['누적 유류 사용량(L)']!.text)!,
                      risk: 0,
                    );
                    await widget.store.registerVehicle(v);
                    if (context.mounted) {
                      setState(() => saving = false);
                      Navigator.pop(context, v.id);
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        saving = false;
                        error = e is ArgumentError
                            ? e.message.toString()
                            : '등록하지 못했습니다. 다시 시도해 주세요.';
                      });
                    }
                  }
                },
          child: Text(saving ? '저장 중…' : '차량 등록 완료'),
        ),
      ],
    ),
  );
}
