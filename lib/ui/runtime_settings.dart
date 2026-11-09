import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'dart:io';

import 'package:go_router/go_router.dart';

import '../data/adaptive_runtime.dart';
import '../data/model_execution.dart';
import '../data/store.dart';
import 'components.dart';

class RuntimeSettingsPanel extends ConsumerWidget {
  const RuntimeSettingsPanel({super.key});
  String tierName(ModelTier t) => switch (t) {
    ModelTier.basic => '기본',
    ModelTier.enhanced => '확장',
    ModelTier.generation => '생성',
  };
  String gib(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(adaptiveRuntimeProvider);
    final d = r.device;
    return Panel(
      title: '분석 기능·자료 관리',
      subtitle: '책자와 사진 분석에 필요한 자료를 추가하거나 처리 설정을 바꿉니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d != null)
            Text(
              '메모리 ${gib(d.totalRamBytes)} · 현재 여유 ${gib(d.availableRamBytes)}\n저장 공간 여유 ${gib(d.freeStorageBytes)}',
            ),
          if (r.detectionError != null) Text(r.detectionError!),
          Text(
            '카메라: ${r.cameraOpenFailed ? '연결을 확인해 주세요' : d?.cameraStatusLabel ?? '확인 중'}',
          ),
          Text(
            '현재 처리 설정: ${tierName(r.selectedTier)} · 추가 문장 정리 ${r.generationEnabled ? '시험 가능' : '사용 안 함'}',
          ),
          const Text('남은 정비거리는 등록한 주기와 마지막 교환 기록으로 계산합니다.'),
          Text(
            r.installedModels.isEmpty
                ? '추가된 책자·사진 분석 자료가 없습니다.'
                : '추가 기능 ${r.installedModels.length}개 준비됨',
          ),
          TextButton(
            onPressed: () async {
              const channel = MethodChannel('maintenance/local_files');
              String? path;
              try {
                path = await channel.invokeMethod<String>('pickEmbedding');
                if (path == null) return;
                await r.installEmbedding(path);
                if (r.modelInfo['corpusDatabasePath'] is String) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '책자 ${r.modelInfo['corpusDocumentCount']}개 · ${r.modelInfo['corpusPageCount']}쪽 · 페이지 이미지 ${r.modelInfo['corpusImagePageCount'] ?? 0}쪽을 반입했습니다. 책자 검색 메뉴에서 질문해 주세요.',
                        ),
                      ),
                    );
                  }
                  return;
                }
                final knowledgePath = r.modelInfo['knowledgePath'] as String;
                final bundle = KnowledgeBundle.decode(
                  await File(knowledgePath).readAsString(),
                );
                if (!context.mounted) return;
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('책자 찾기 기능 준비 완료 · 참고 내용 추가'),
                    content: Text(
                      '문서 근거 ${bundle.library.evidence.length}개 · 검토 대기 실적 ${bundle.library.knowledge.pending.length}건\n품번과 차량 적용조건은 별도로 확인합니다. 근거도 반입하시겠습니까?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('근거 반입 취소'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('근거 반입'),
                      ),
                    ],
                  ),
                );
                if (yes == true) {
                  await ref.read(storeProvider).importKnowledge(bundle);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        yes == true
                            ? '책자 찾기 자료를 추가했습니다. 이 차량에 맞는 내용인지 확인해 주세요.'
                            : '찾기 기능을 준비했습니다. 연결된 자료가 없으면 입력한 말로 찾습니다.',
                      ),
                    ),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('반입하지 못했습니다. 파일·공간·기존 반입 ID를 확인해 주세요.'),
                    ),
                  );
                }
              } finally {
                if (path != null) {
                  await channel.invokeMethod<bool>('releaseBackup', {
                    'path': path,
                  });
                }
              }
            },
            child: const Text('책자 찾기 자료 추가하기 (.mrag)'),
          ),
          if (r.modelInfo['corpusDatabasePath'] is String)
            TextButton.icon(
              onPressed: () => context.go('/manual-search'),
              icon: const Icon(Icons.menu_book),
              label: Text('책자 검색 열기 · ${r.modelInfo['corpusPageCount']}쪽'),
            ),
          TextButton(
            onPressed: () async {
              const channel = MethodChannel('maintenance/local_files');
              String? path;
              try {
                path = await channel.invokeMethod<String>('pickBackup');
                if (path == null) return;
                await r.installVision(path);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '사진 속 물체 찾기 기능을 추가했습니다. 차량 부품의 고장을 판단하는 기능은 아닙니다.',
                      ),
                    ),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '사진 분석 기능을 추가하지 못했습니다. 파일과 저장 공간을 확인해 주세요.',
                      ),
                    ),
                  );
                }
              } finally {
                if (path != null) {
                  await channel.invokeMethod<bool>('releaseBackup', {
                    'path': path,
                  });
                }
              }
            },
            child: const Text('사진 속 물체 찾기 기능 추가하기'),
          ),
          if ((d?.androidApi ?? 0) >= 28)
            TextButton(
              onPressed: () async {
                const channel = MethodChannel('maintenance/local_files');
                String? path;
                try {
                  path = await channel.invokeMethod<String>('pickLlm');
                  if (path == null) return;
                  await r.installLlm(path);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '문장 정리 기능을 추가했습니다. 정비지원에서 원문 요약을 확인할 수 있습니다.',
                        ),
                      ),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '문장 정리 기능을 추가하지 못했습니다. 기기 지원 여부와 파일·저장 공간을 확인해 주세요. 책자 검색은 계속 사용할 수 있습니다.',
                        ),
                      ),
                    );
                  }
                } finally {
                  if (path != null) {
                    await channel.invokeMethod<bool>('releaseBackup', {
                      'path': path,
                    });
                  }
                }
              },
              child: const Text('원문 문장 정리 기능 추가하기 (.gguf)'),
            ),
          TextButton(
            onPressed: () async {
              const channel = MethodChannel('maintenance/local_files');
              String? path;
              try {
                path = await channel.invokeMethod<String>('pickBackup');
                if (path == null) return;
                await r.installSystemPilot(path);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '정비 종류를 제안하는 기능을 추가했습니다. 제안을 확인한 뒤 선택해 주세요.',
                      ),
                    ),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '정비 분류 기능을 추가하지 못했습니다. 파일과 저장 공간을 확인해 주세요.',
                      ),
                    ),
                  );
                }
              } finally {
                if (path != null) {
                  await channel.invokeMethod<bool>('releaseBackup', {
                    'path': path,
                  });
                }
              }
            },
            child: const Text('정비 내용을 종류별로 나누는 기능 추가하기 (.msystem)'),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('runtime-ceiling-${r.userCeiling?.name}'),
            initialValue: r.userCeiling?.name ?? 'auto',
            decoration: const InputDecoration(labelText: '기기 처리 강도'),
            items: [
              const DropdownMenuItem(value: 'auto', child: Text('자동')),
              for (final t in ModelTier.values.where(
                (t) => t.index <= r.automaticTier.index || t == r.userCeiling,
              ))
                DropdownMenuItem(value: t.name, child: Text(tierName(t))),
            ],
            onChanged: (v) => r.setCeiling(
              ModelTier.values.where((t) => t.name == v).firstOrNull,
            ),
          ),
          if (r.settingsError != null) Text(r.settingsError!),
          TextButton(
            onPressed: r.refreshDevice,
            child: const Text('기기 상태 다시 확인'),
          ),
        ],
      ),
    );
  }
}
