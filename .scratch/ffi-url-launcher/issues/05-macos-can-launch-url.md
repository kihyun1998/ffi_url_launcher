# 05 — macOS에서 `canLaunchUrl`이 답한다

**What to build:** macOS에서도 URL을 열기 전에 처리 가능한 앱이 있는지 물어볼 수 있다. Windows와 같은 API, 같은 의미. 이 티켓이 끝나면 두 플랫폼의 공개 API 표면이 완전히 대칭이 된다.

**설계 배경**

판정은 `[[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:url]`이 nil인지로 한다. 이것이 03에서 이음새 메서드를 `schemeRegistered(String)`이 아니라 `canOpen(Uri)`로 이름 지은 이유다 — macOS는 스킴 등록 여부를 묻는 게 아니라 URL 전체를 처리할 앱을 조회한다.

`URLForApplicationToOpenURL:`은 조회만 하므로 부작용이 없다. Windows 쪽과 마찬가지로 CI에서 실제 OS 상대로 검증할 수 있다.

참고: 원본 `url_launcher_macos`도 정확히 이 API를 쓴다 (`workspace.urlForApplication(toOpen:) != nil`). deprecated된 `LSCopyDefaultApplicationURLForURL`이 아니라 이쪽이 현행 API다.

**Blocked by:** 03, 04

03이 `canOpen(Uri)` 이음새와 공개 API 형태를 정하고, 04가 macOS의 objc 런타임 헬퍼와 `NSWorkspace` 접근을 만든다. 둘 다 있어야 시작할 수 있다.

**Status:** ready-for-agent

- [ ] macOS에서 `canLaunchUrlSync` / `canLaunchUrl`이 `https://` URL에 대해 `true`를 반환한다
- [ ] 설치되지 않은 앱의 커스텀 스킴에 대해 `false`를 반환한다
- [ ] 판정이 `URLForApplicationToOpenURL:`의 nil 여부로 이루어진다
- [ ] 반환된 객체의 수명 관리가 04에서 정한 규약과 일치한다
- [ ] 실제 시스템을 상대로 하는 통합 테스트가 존재하며, 아무 앱도 실행하지 않는다
- [ ] Fake 이음새 주입 단위 테스트가 true/false 경로를 덮는다
- [ ] Windows와 macOS의 공개 API 시그니처가 완전히 동일하다 (플랫폼별 분기가 공개 표면에 새지 않는다)
