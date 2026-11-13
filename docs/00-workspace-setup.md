# 저장소와 개발 환경

기준일: 2026-11-13. 과거 연결·검증 기록은 날짜별 QA 문서에서 확인한다.

## 저장소

| 항목 | 값 |
| --- | --- |
| 프로젝트 | 정비온 — 기동장비 데이터 기반 AI 정비관리 |
| GitHub | https://github.com/Superkid0714/2026-military-mobile |
| 원격 / 기준 브랜치 | `origin` / `main` |
| 작성자 | Lucel (`Superkid0714`) |
| 앱 패키지 | `military_maintenance` |
| 앱 버전 | `0.9.30+45` (`pubspec.yaml` 기준) |
| Android applicationId | `com.superkid.military.military_maintenance` |

로컬 작업 지침은 프로젝트 루트의 `AGENTS.md`를 따른다. 해당 환경에서는 시스템 Git 대신 지정된 Codex 번들 Git을 사용한다. 작성자 설정과 원격 상태는 작업 시 직접 확인하며 이 문서의 과거 확인값을 실시간 상태로 해석하지 않는다.

## 개발 도구

| 항목 | 소스 설정 / 확인 환경 |
| --- | --- |
| Dart | `^3.13.0` |
| 확인한 Flutter / Dart | 3.47.7 / 3.13.5 |
| Android minSdk | 24 |
| compileSdk / targetSdk / NDK | Flutter SDK가 제공하는 값 |
| Java / Kotlin 컴파일 타깃 | 17 |
| 확인한 빌드용 JDK | Temurin 21 |
| Android Gradle Plugin / Gradle wrapper | 9.1.0 / 9.3.1 |
| ONNX Runtime Android | 1.23.2, 로컬 AAR 사전 준비 |

이 조합은 현재 개발 환경의 실행 결과다. 임의의 Flutter·JDK 조합이나 모든 Android 기기의 호환성을 뜻하지 않는다.

## 설치와 실행

```sh
git clone https://github.com/Superkid0714/2026-military-mobile.git
cd 2026-military-mobile
flutter doctor -v
flutter pub get
```

Android 빌드 전에 PowerShell로 ONNX Runtime을 준비한다.

```sh
pwsh -File tools/provision_onnx_android.ps1
```

- 생성 위치: `.tools/android-libs/onnxruntime-android-1.23.2.aar`
- 검증 SHA-256: `82048d1f462218adae4ba76477089ab0ba76093d84f733540066db1a8ba6b827`
- 앱 실행 중 다운로드하는 것이 아니라 개발 PC에서 빌드 전에 준비하는 절차다.

```sh
flutter analyze
flutter test
flutter devices
flutter run -d <기기ID>
flutter build apk --release --target-platform android-arm64
```

SDK를 전역 PATH 대신 별도 경로에 설치했다면 해당 Flutter 실행 경로를 사용한다. `android/local.properties`의 `flutter.sdk`, `sdk.dir`와 `JAVA_HOME`은 실제 개발 PC에 맞춘다. 이 로컬 설정은 커밋하지 않는다.

현재 release 빌드는 개발용 서명을 사용한다. 정식 배포용 서명 설정과 서명 키 관리는 별도 작업이다.

## 선택 기능 준비

- 기본 기록 관리·사진 촬영·마크 저장에는 선택 모델 가중치가 필요하지 않다.
- 임베딩 검색, LLM 요약, 실제 Vision 추론은 관련 모델·네이티브 라이브러리·검색 자료를 별도로 준비한다.
- 디지털 트윈의 순차 검사 시연은 실제 추론과 분리된 고정 시나리오다.
- `.tools/front-vision-assets`가 있으면 Android 빌드에 로컬 전면 부위 모델이 포함될 수 있다. 해당 모델과 학습 자료는 공개 저장소에 올리지 않는다.
- 문서 반입·검색 구성은 [전체 책자 RAG](14-manual-rag.md)와 [문서 이미지](18-offline-manual-images.md)를 참고한다.

## 검증 기록

최신 변경 사항은 [2026-11-13 변경·검증 기록](43-ui-and-inspection-2026-11-13.md)을 따른다. 현재 환경의 Flutter 분석 서버는 LSP 메시지 파싱 오류로 종료되는 문제가 있어, `flutter analyze` 실패와 대체 `dart analyze lib test` 결과를 구분해 기록한다.

초기 태블릿 연결과 개발 환경 구성의 과거 근거는 [2026-11-03 QA](07-qa-2026-11-03.md), [태블릿 설치](08-tablet-qa-2026-11-03.md), [후속 수정](09-fixes-2026-11-03.md)에 남아 있다.
