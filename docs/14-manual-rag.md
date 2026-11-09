# 전체 책자 RAG

## 일반 앱에서 사용

1. 데이터 관리 → 기기 사양·모델 단계에서 v2 `.mrag` 묶음을 반입한다.
2. 왼쪽의 **책자 검색 · RAG** 또는 AI 정비지원의 **전체 책자 검색 · RAG**를 연다.
3. 전체 책자 또는 특정 문서를 선택하고, 필요하면 본문 부품 필터를 선택한다.
4. 질문을 입력하고 검색한다. 먼저 관련 원문이 표시되고, 선택 요약 모델이 준비되면 짧은 인용 답변을 추가한다.
5. 출처 버튼과 **인용 원문 전체 보기**에서 해당 PDF 파일명·PDF 쪽·인쇄면 위치·추출 본문·원본 해시를 확인한다.

이 화면은 참고 문서 검색이다. 실제 차량의 연식·엔진·부대 기준이나 교환주기를 자동 확정하지 않는다. 그림·전기회로를 해석하는 PDF 뷰어가 아니라 출처가 연결된 추출 원문을 보여 준다. 수치·교환주기는 원문과 기존 등록 규칙에서 확인한다. 질문 상한은 검색 500자, 선택 요약 120자이며 초과 질문은 검색 원문을 유지한다.

## 구현

- `ManualRag`와 `manual_rag.dart`: 임베딩·BM25·RRF 검색, 문서·본문 부품 범위, 출처 생성, 네이티브 실패 시 키워드 검색.
- `ManualSearchScreen`: 문서 선택 → 한글 질문 → 검색 → 인용 답변 → 전체 원문 흐름. 차량을 등록하지 않아도 책자 참고 검색 경로를 사용할 수 있다.
- `EmbeddingFiles`: 기존 v1 묶음 호환을 유지하면서 SQLite corpus를 담은 v2 묶음을 검증·설치한다. 전체 파일 SHA-256, 실행 설정, DB 무결성을 검증한 뒤 staging 디렉터리를 교체한다.
- 실행 중 서버·다운로드·외부 API를 사용하지 않는다. 공용 모델과 문서는 PC에서 준비해 로컬 파일로 반입한다.

이전의 JSON 색인은 4MiB 제한을 유지한다. v2는 같은 임베딩 모델과 작은 descriptor JSON에 `corpus.sqlite`를 추가한다. DB는 128MiB, 전체 묶음은 기존 256MiB 제한을 따른다. 페이지 텍스트·PDF 출처와 512차원 float32 벡터를 SQLite에 보관하고, 읽기 전용 검색을 별도 Dart isolate에서 수행한다. UI에 전체 벡터 JSON을 적재하지 않는다. 검색마다 페이지 범위로 벡터를 읽고 최종 5개 원문만 UI로 돌려준다.

키워드는 문서 길이·단어 빈도·문서 빈도와 여러 단어의 부품명을 반영한다. 임베딩과 키워드 순위를 RRF로 결합하며, 정확한 키워드 근거 1위가 최종 5개에서 사라지지 않도록 보존한다. 최소한의 단어 일치 없이 임베딩 유사도만 높은 문서는 반환하지 않는다. 이 방식은 검색 휴리스틱이며 관련성·정답 확률이 아니다. 원문이 없는 질문에 자유 답변을 생성하지 않는다.

요약은 기존의 완전 문장·원문 인용 검증을 재사용한다. 검색된 최대 5개 원문에서 질문 관련 근거 2개와 안전 문장을 선택하며, 숫자·원문 밖 설명·불완전한 문장·생성 실패는 원문 표시로 돌아간다. 사용자가 인용을 통해 문맥을 확인할 수 있다.

## PC 색인 구성

원문·추출·질문·정답·벡터·기기 결과는 모두 `private/`에 보관한다. 공개 저장소나 APK 자산에 넣지 않는다. 묶음의 Apache 2.0 표시는 공개 임베딩 모델의 라이선스이며 원본 PDF의 권리를 바꾸지 않는다.

```sh
python tools/ingest_local_pdfs.py --inputs private/pdf-intake/inputs.json --output private/pdf-intake
python tools/build_manual_corpus.py --source private/pdf-intake/pages.sqlite --base private/reference/bundle --output private/manual-corpus
```

두 번째 명령은 고정된 공개 모델·토크나이저와 검증된 기존 모델 bundle을 사용한다. 페이지 단위 원문에서 토큰 중첩 조각을 만들고 배치 추론으로 벡터를 계산한다. 실제 운용·정비 실적과 글꼴 매핑 의심 문서는 지침서 색인에서 제외한다. 빈 텍스트·도면과 실제 빈 페이지를 구분하고 원문 화면과 대조한다. 원문에 없는 조건이나 수치를 만들지 않는다.

## 검사

```sh
flutter test test/manual_rag_test.dart
MANUAL_QA_DIR=private/manual-corpus flutter test tools/manual_corpus_qa_test.dart
python tools/run_rag_device_qa.py --adb /path/to/adb --serial DEVICE_ID --entry manualRagDeviceProbe --output private/manual-corpus/device
python tools/run_manual_ui_qa.py --adb /path/to/adb --serial DEVICE_ID --output private/manual-corpus/ui
```

기기 진단은 최신 debug APK·계측 APK, `cache/maintenance-import-probe.mrag`, 필요 시 `cache/maintenance-import-llm.gguf`, `files/manual-rag-questions.json`을 준비한 뒤 실행한다. 일반 화면 검사는 잠금 해제가 필요하며 화면 유지 설정을 임시 적용하고 복원한다. 두 실행기는 실행 ID를 대조해 오래된 결과를 새 결과로 세지 않는다.

코어 회귀 검사는 범위 밖 문서, 근거 없음, 출처·유니코드 조각, 모델·벡터 불일치 거부, 임베딩 실패 시 키워드 대체를 확인한다. 실제 자료용 검사는 별도 비공개 질문·정답을 사용한다. 같은 사례를 보고 개선한 결과를 독립 홀드아웃 정확도나 실차 판단 성능으로 해석하지 않는다.
