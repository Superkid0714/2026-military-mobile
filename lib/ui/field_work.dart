import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/store.dart';
import 'components.dart';

Future<void> showFieldWorkEditor(
  BuildContext context,
  AppStore store, {
  FieldWorkKind kind = FieldWorkKind.parts,
  String? vehicleId,
  String part = '',
}) => showDialog<void>(
  context: context,
  builder: (_) => _FieldWorkEditor(
    store: store,
    kind: kind,
    vehicleId: vehicleId,
    part: part,
  ),
);

class FieldWorkScreen extends ConsumerWidget {
  const FieldWorkScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final ids = store.dashboardVehicles.map((v) => v.id).toSet();
    final items = store.fieldWork
        .where((item) => ids.contains(item.vehicleId))
        .toList();
    return ListView(
      children: [
        const PageTitle('현장 요청', '부속 요청과 인식 오류를 관리하세요.'),
        const Text('태블릿에 저장됩니다. 부대 시스템으로 자동 전송되지는 않습니다.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: store.dashboardVehicles.isEmpty
                  ? null
                  : () => showFieldWorkEditor(context, store),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('부속 요청 작성'),
            ),
            OutlinedButton.icon(
              onPressed: store.dashboardVehicles.isEmpty
                  ? null
                  : () => showFieldWorkEditor(
                      context,
                      store,
                      kind: FieldWorkKind.feedback,
                    ),
              icon: const Icon(Icons.feedback_outlined),
              label: const Text('인식 오류 제보'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (items.isEmpty) empty('저장된 요청이 없습니다.'),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              title: item.kind == FieldWorkKind.parts
                  ? '부속 요청 · ${item.part}'
                  : '인식 오류 · ${item.part}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${vehicleLabel(item.vehicleId)} · ${item.created.split('T').first}',
                  ),
                  const SizedBox(height: 6),
                  if (item.kind == FieldWorkKind.parts)
                    Text(
                      '품번: ${item.partNumber.isEmpty ? '확인 필요' : item.partNumber} · ${item.quantity}개',
                    ),
                  Text(item.note),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        item.closed ? '처리 완료' : '확인 대기',
                        style: TextStyle(
                          color: item.closed ? green : muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await store.closeFieldWork(item, !item.closed);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('변경하지 못했습니다. 다시 시도해 주세요.'),
                                ),
                              );
                            }
                          }
                        },
                        child: Text(item.closed ? '다시 확인' : '처리 완료로 변경'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('요청을 삭제할까요?'),
                              content: const Text('저장한 요청 내용이 삭제됩니다.'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('취소'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('삭제'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          try {
                            await store.deleteFieldWork(item.id);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('삭제하지 못했습니다. 다시 시도해 주세요.'),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('삭제'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FieldWorkEditor extends StatefulWidget {
  const _FieldWorkEditor({
    required this.store,
    required this.kind,
    this.vehicleId,
    required this.part,
  });
  final AppStore store;
  final FieldWorkKind kind;
  final String? vehicleId;
  final String part;
  @override
  State<_FieldWorkEditor> createState() => _FieldWorkEditorState();
}

class _FieldWorkEditorState extends State<_FieldWorkEditor> {
  final form = GlobalKey<FormState>();
  late final part = TextEditingController(text: widget.part);
  final number = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final note = TextEditingController();
  late String? vehicle =
      widget.vehicleId ?? widget.store.dashboardVehicles.firstOrNull?.id;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    part.dispose();
    number.dispose();
    quantity.dispose();
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
      await widget.store.saveFieldWork(
        FieldWork(
          id: widget.store.newId('FIELD'),
          vehicleId: vehicle!,
          kind: widget.kind,
          part: part.text.trim(),
          note: note.text.trim(),
          partNumber: widget.kind == FieldWorkKind.parts
              ? number.text.trim()
              : '',
          quantity: widget.kind == FieldWorkKind.parts
              ? int.parse(quantity.text)
              : 1,
          created: widget.store.clock().toIso8601String(),
        ),
      );
      if (mounted) Navigator.of(context).pop();
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
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text(widget.kind == FieldWorkKind.parts ? '부속 요청 작성' : '인식 오류 제보'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: vehicle,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '차량'),
                  items: [
                    for (final v in widget.store.vehicles)
                      DropdownMenuItem(
                        value: v.id,
                        child: Text(vehicleLabel(v.id)),
                      ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) => setState(() => vehicle = value),
                  validator: (value) => value == null ? '차량을 선택해 주세요.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: part,
                  enabled: !saving,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: '부품 이름'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '부품 이름을 입력해 주세요.'
                      : null,
                ),
                if (widget.kind == FieldWorkKind.parts) ...[
                  TextFormField(
                    controller: number,
                    enabled: !saving,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: '품번 (선택)',
                      helperText: '책자나 부품에서 확인한 품번을 입력하세요.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: quantity,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '수량'),
                    validator: (value) {
                      final count = int.tryParse(value ?? '');
                      return count == null || count < 1 || count > 999
                          ? '1~999개로 입력해 주세요.'
                          : null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: note,
                  enabled: !saving,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: widget.kind == FieldWorkKind.parts
                        ? '요청 사유'
                        : '어떤 부분이 달랐나요?',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '내용을 입력해 주세요.'
                      : null,
                ),
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
          onPressed: saving ? null : save,
          child: Text(saving ? '저장 중…' : '저장'),
        ),
      ],
    ),
  );
}
