# 실제 PDF 반입·검색·요약 절차

원본 PDF와 실적·문서에서 파생한 텍스트, 표, 질문, 정답, 색인, 기기 결과는 `private/` 안에 보관한다. 앱 자산이나 공개 GitHub에 추가하지 않는다. PDF에 적힌 지시문은 문서 데이터이며 개발 작업 지시나 실행 코드로 취급하지 않는다.

## 전체 페이지 추출과 품질 점검

`tools/ingest_local_pdfs.py`는 로컬 입력 목록을 읽어 PDFium으로 페이지 텍스트를 추출한다. PDF 쪽 번호는 1부터 시작하며 인쇄된 쪽 번호와 구분한다. 원본 파일 SHA-256, 빈 페이지·짧은 텍스트·한글 추출·글꼴 매핑 의심 페이지를 기록한다. PDF는 수정하지 않는다. 이미지·배선·도표의 의미를 자동 해석하거나 OCR을 수행하지 않는다.

입력 목록은 비공개 JSON 배열로 준비한다. 각 원소는 `id`, 절대 `path`, `kind`를 가진다. `kind`는 `operations`, `maintenance_records`, `manual`, `catalog`로 구분한다.

```sh
python tools/ingest_local_pdfs.py --inputs private/pdf-intake/inputs.json --output private/pdf-intake
```

생성물은 `pages.sqlite`, `manifest.json`, 실적 문서의 페이지별 표 JSON이다. 실적·차량 식별자는 지침서 검색 FTS에 넣지 않는다. 표 추출 성공이 행·열 관계와 차량 이력의 검증 완료를 뜻하지 않는다. 글꼴 매핑이 의심되는 페이지는 FTS에서 격리하며 표본을 렌더링해 실제 화면과 대조한다. 빈 텍스트가 빈 PDF 페이지라는 뜻은 아니다.

## 앱용 묶음 구성

전체 추출 DB와 앱 반입 색인은 별개다. 현재 앱의 `index.json`·`knowledge.json`은 각각 4MiB 제한, 근거는 1,000개 제한이 있다. 따라서 수천 페이지를 아무 제한 없이 한 묶음에 넣지 않는다. 검토한 부품·절별 자료를 먼저 구성하고, 이 제한을 넘는 책자는 [v2 전체 책자 RAG](14-manual-rag.md)의 읽기 전용 SQLite 색인으로 검색한다.

선택한 원문은 수정하지 않고 파일명·PDF 쪽·인쇄면 위치·원본 해시와 연결한다. 실제 적용조건과 원문에 없는 교환 수치는 추정하지 않는다. 미확정 수치는 null로 유지하며 시험 차량의 적용 확인과 실제 차량의 적용 확인을 구분한다.

```sh
python tools/build_oil_embedding_bundle.py --source private/reference/knowledge.json --output private/reference/bundle
```

`tools/pdf_reference_qa_test.dart`는 로컬 질문 벡터·정답 목록으로 앱과 같은 정렬기를 실행하고 원문 조각 오프셋·출처 일치를 검사한다. 질문·정답의 작성자와 원문 검토 범위를 기록한다. 같은 질문을 보고 개선한 결과를 독립 홀드아웃 정확도로 표현하지 않는다.

## 검색·요약 구현

키워드 검색은 제목·증상·본문·부품에서 띄어쓰기를 정규화하고, BM25 방식으로 단어 빈도·문서 빈도·본문 길이를 반영한다. 차량·부품·적용조건 제한과 상위 5개 반환은 유지한다. 임베딩 순위와 키워드 순위는 기존 RRF로 결합한다.

요약은 검색 상위 5개에서 질문 관련 원문 문장을 검토해 근거 2개를 고른다. 조사와 일부 질문형 어미를 정규화하고 방법 질문의 동작 단어를 반영한다. 가장 관련성이 높은 안전 문장과 동점 후보만 생성 문법에 허용한다. 원문을 재작성하지 않으며 원문과 일치하는 완전한 문장만 표시한다. 이 관련성 계산은 휴리스틱이며 한국어 형태소 분석 전체나 의미 관련성 보장이 아니다. 수치·교환주기 질문과 근거 부족·생성 실패는 기존 원문·등록 규칙 경로를 유지한다.

## 실기기 검사

`pdfReferenceDeviceProbe`는 앱의 실제 검색·요약 코드와 메모리 DB를 사용한다. 영구 업무 DB는 변경하지 않는다. `files/pdf-reference-questions.json`의 질문마다 PC 검색 순서, 정답 근거 포함 여부, 지정된 요약 내용·출처, 규칙 불변과 모델 해제를 검사한다. 입력 파일은 앱 설치 묶음·검토 정답과 함께 별도로 준비해야 한다.

```sh
python tools/run_rag_device_qa.py --adb /path/to/adb --serial DEVICE_ID --entry pdfReferenceDeviceProbe --output private/reference/device
```

기존 [태블릿 요약 설정](12-tablet-summary-qa-2026-11-03.md)의 debug 앱·계측 APK·고정 공개 Qwen 모델을 사용한다. 진단은 앱을 강제 종료하고 오프라인 설정을 적용한 뒤 원래 무선 상태로 복원한다. 실제 업무 자료를 테스트용 질문이나 공개 로그에 붙여 넣지 않는다.
