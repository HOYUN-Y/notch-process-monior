# 작업 기록

## 2026-11-08 — 1차 MVP 구현 (구현자)

**한 일**: SwiftPM 기반 macOS 앱(`MenuBarGather`)과 라이브러리(`MenuBarKit`), 검증용 CLI(`menubar-dump`), 시험 항목(`menubar-fixture`), 빌드 스크립트(`scripts/build-app.sh`, `scripts/build-fixture.sh`), 테스트, README를 만들었다. 커밋·설치는 하지 않았다.

**주요 결정과 이유**
- 최소 OS는 macOS 14: `onKeyPress` 등 키보드 처리와 SwiftUI 기능을 외부 의존성 없이 쓰기 위해.
- Xcode 프로젝트 대신 SwiftPM + 스크립트로 .app 번들 조립(Info.plist, ad-hoc 서명). 재빌드마다 서명이 바뀌어 권한 재확인이 필요할 수 있다(README에 기재).
- 조회는 `NSWorkspace` 실행 앱 중 activationPolicy가 prohibited가 아닌 것만 대상(헬퍼 프로세스 제외). 항목은 `AXExtrasMenuBar`에서만 읽는다. 다른 호환 경로는 필요가 확인되지 않아 만들지 않았다. 화면 좌표로는 항목을 제외하지 않고, 노치 겹침은 표시 문구로만 쓴다.
- 요소별 AX 타임아웃은 자식에 상속되지 않으므로 시스템 전체 타임아웃을 함께 설정하고, 앱 하나당 3초 예산과 "첫 응답 없음에서 중단" 규칙을 둔다.
- AXPress의 반환값은 성공 신호로 믿을 수 없다(메뉴가 열렸는데 -25205 또는 타임아웃). 그래서 "응답 없음/미확인"은 실패가 아니라 실행됐을 수 있는 상태로 표시하고 다시 보내지 않는다.
- 앱 종료는 `.app` 소유 앱에만 제공하고 `NSRunningApplication.terminate()`만 쓴다. 요청 수락과 실제 종료를 구분해 실제 종료를 관찰한 뒤 목록에서 지운다.
- `Scanner` 이름은 Foundation과 충돌해 `AXScanner`로 지었다.

**남은 일·주의점**: docs/PLAN.md의 미완료 항목, technical-validation.md의 미검증 목록 참고. 앱 자체의 손쉬운 사용 권한은 허용하지 않았다(사용자 조작 필요). 목록 화면 검증은 터미널(Ghostty)의 권한을 이어받은 프로세스로 실행해 수행했다.

## 2026-11-08 — 감독 검수 반영과 노치 안쪽 항목 확인 (구현자)

- 감독 검수: `swift test` 7개 통과, `codesign --verify --deep --strict`, plist, 셸 구문 검사 통과. 권한 안내 화면의 navy/slate와 종료 확인 창(앱 이름·PID·취소/종료 요청)을 감독이 확인했다. 검수 지적(ownerAppURL의 .app 확인, 조회 중 권한 해제 처리, 앱별 시간 예산, 스캔과 요청의 겹침, fixture 인자 범위)은 반영됐다.
- 문서: product-plan 8절의 "구현은 후속 지시를 기다린다" 문단을 구현 승인·진행 현황으로 고쳤다.
- 노치 안쪽 실제 항목 확인: Tailscale 항목 하나(좌표가 노치에 완전히 포함)에 메뉴 열기 `AXPress`를 1회 요청했다. 반환은 타임아웃이었지만 3.2초 뒤 메뉴 창이 노치 아래 y 40에 관찰됐다. 메뉴 안 항목은 누르지 않았고 키 입력도 보내지 않았다. 육안 확인은 없다. 자세한 내용은 technical-validation.md.
- 이 단계에서는 소스, 앱 번들, 서명을 바꾸지 않았고 앱을 다시 빌드하거나 프로세스를 재시작하지 않았다(사용자가 앱 권한을 허용하는 중).
- 남은 일: 앱 자체 권한 허용 후 실행 확인, 외장 모니터·자동 숨김·VoiceOver·키보드, 목록·종료 화면의 시각 확인.

## 2026-11-08 — PR·병합 승인 (구현자 기록)

- 사용자가 PR 생성과 병합까지 명시적으로 승인했다. Git 브랜치(`feat/menu-bar-gather`)·커밋·PR·병합은 감독이 수행하며, 진행·병합 상태는 이 문서가 아니라 GitHub PR을 기준으로 확인한다. 구현자는 Git 작업을 하지 않았다.
- 권한을 허용한 상태에서의 앱 검수는 아직 미완료다.
- 0.1.0 MVP로 올리며, technical-validation.md와 PLAN.md의 미검증·남은 한계는 그대로 공개한다. 코드와 앱 번들은 변경하지 않았다.

## 2026-11-09 — 권한 "다시 확인" 무반응 수정 (구현자, 브랜치 fix/accessibility-permission-refresh)

- 원인: 시스템에 등록된 접근성 허용 기록의 서명 요건(cdhash)이 실행 중인 빌드와 맞지 않아 거부됨. 설정의 토글이 켜져 있어도 발생할 수 있고, 토글·재실행만으로는 해결되지 않는다. 앱이 거부 상태를 화면에 알리지 않아 무반응처럼 보였다. 근거와 한계는 technical-validation.md.
- 수정 파일: `Sources/MenuBarKit/Model.swift`(확인 결과 문구 함수), `Sources/MenuBarGather/Store.swift`(마지막 확인 상태, Finder에서 앱 위치 선택), `Sources/MenuBarGather/ContentView.swift`(권한 안내 화면), `Tests/MenuBarKitTests/LogicTests.swift`(테스트 1개 추가), `README.md`(복구 안내, 재빌드 서명 표현 정정), docs.
- 결정: 허용 판정은 기존 API 결과를 그대로 쓰고 서명 요건 완화·권한 초기화·인증서 설치·허용 강제는 하지 않는다. 재시작 버튼은 원인을 고치지 못해 추가하지 않았다. 처음에 넣은 확인 결과 텍스트의 접근성 라벨이 문구를 가려서 제거했다.
- 빌드: 수정 후 번들을 만들었다(검증 중 발견한 라벨 문제 때문에 한 번 더 만들어 최종 번들은 마지막 것 하나).
- 남은 일: 사용자의 재등록과 앱 자체 권한으로의 조회 확인(미완료).
- 독립 검수자가 최신 코드에서 차단 결함이 없고 별도 경로의 `swift test` 8개와 `git diff --check`가 통과했다고 보고했다. 사용자의 실제 재등록과 앱 자체 권한으로의 조회 확인은 아직 미완료다. technical-validation.md의 두 표현(추가 번들 미발견, 동일 번들 재시작만으로는 해결되지 않음)을 보정했다.
