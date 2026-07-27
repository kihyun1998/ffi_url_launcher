# 07 — pub.dev에 올릴 수 있는 상태가 된다

> **GitHub issue: #7** — the working surface. This file is the long-form
> design record; the issue carries state, labels and blocking edges.

**What to build:** 처음 보는 Dart CLI 개발자가 pub.dev에서 이 패키지를 발견하고, README만 읽고 올바르게 — 그리고 안전하게 — 쓸 수 있다. `dart pub publish --dry-run`이 경고 없이 통과한다.

**설계 배경**

이 티켓의 핵심은 파일 몇 개 채우는 것이 아니라 **거짓 안전감을 만들지 않는 것**이다. 02의 검증은 부분 방어다 — 드라이브 문자와 UNC 경로는 막지만 `file:///C:/Windows/System32/calc.exe`는 통과시킨다. "URL을 검증합니다"라고만 쓰면 호출자가 신뢰할 수 없는 입력을 그대로 넘길 위험이 오히려 커진다. 그래서 **막는 것과 막지 않는 것을 나란히 표로** 보여야 한다.

문서화가 필요한 알려진 비대칭:

- `canLaunchUrl`은 `file:` 스킴에 대해 항상 `true`를 반환한다. 스킴 등록과 확장자 연결이 다른 레이어이기 때문 (03 참조)
- `UrlLaunchException.platformCode`는 Windows에서만 값이 있고 macOS에서는 항상 `null`이다. `NSWorkspace.open`이 BOOL만 반환하기 때문 (04 참조)
- 이 패키지는 진짜 비동기가 아니다. `Future` 시그니처는 미래를 위한 것이고, 실제 호출은 동기다 — macOS의 메인 스레드 요구와 Windows의 COM 아파트먼트 요구 때문에 아이솔레이트로 옮길 수 없다

또한 이 패키지는 `url_launcher`의 코드를 복사하지 않았다. 어떤 OS API를 불러야 하는지만 참고했다. 법적 의무는 없지만 출처를 밝히는 것이 정직하다.

**Blocked by:** 02, 05, 06

**Status:** ready-for-agent

- [ ] `dart pub publish --dry-run`이 경고 0으로 통과한다
- [ ] README에 "막는 것 / 막지 않는 것"이 나란히 표로 제시되고, `file:`이 실행 벡터라는 점이 명시된다
- [ ] README에 `canLaunchUrl`이 `file:`에 항상 `true`라는 한계가 적힌다
- [ ] README에 `platformCode`가 macOS에서 `null`이라는 점이 적힌다
- [ ] README에 Dart CLI 사용 예제와 Flutter 앱 사용 예제가 모두 있다
- [ ] README에 Flutter 의존이 없다는 점과 `dart compile exe`가 동작한다는 점이 명시된다 — 이 패키지를 선택할 이유
- [ ] `url_launcher`를 참고했다는 사실이 README에 밝혀진다
- [ ] LICENSE 파일이 BSD-3-Clause로 존재한다
- [ ] CHANGELOG에 `0.1.0` 항목이 있다
- [ ] pubspec에 `description`, `repository`, `topics`가 채워지고 지원 플랫폼(Windows, macOS)이 선언된다
- [ ] 최소 지원 버전(Windows 10+, macOS 10.14+)이 문서에 명시된다
