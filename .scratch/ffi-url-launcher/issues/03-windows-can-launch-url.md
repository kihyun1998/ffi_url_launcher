# 03 — Windows에서 `canLaunchUrl`이 앱 설치 여부를 답한다

> **GitHub issue: #3** — the working surface. This file is the long-form
> design record; the issue carries state, labels and blocking edges.

**What to build:** 호출자가 URL을 열기 전에 "이걸 처리할 앱이 이 시스템에 있나"를 물어볼 수 있다. 아무것도 열지 않으므로 부작용이 없고, 따라서 CI에서 실제 OS 상대로 검증할 수 있는 첫 기능이다.

**설계 배경**

Windows 판정은 `HKEY_CLASSES_ROOT\<scheme>`에 `URL Protocol` 값이 있는지로 한다. HKCR은 `HKLM\Software\Classes`(전체 사용자)와 `HKCU\Software\Classes`(현재 사용자)의 병합 뷰라, 요즘 흔한 per-user 설치 앱도 함께 잡힌다.

이 방식에 변별력이 있다는 것은 실제 머신에서 확인했다 — 설치된 앱의 스킴은 `true`, 미설치 앱과 존재하지 않는 스킴은 `false`가 나온다.

**알려진 한계 (의도된 것, 07에서 문서화):** `file:` 스킴은 항상 `true`다. 스킴 등록 여부와 확장자 연결 여부는 레지스트리의 다른 레이어라, `file:///x.알수없는확장자`는 `canLaunchUrl`이 `true`인데 `launchUrl`은 `SE_ERR_NOASSOC`로 실패한다. 확장자까지 확인하려면 `AssocQueryStringW`가 필요한데, 지금은 넣지 않는다.

**이음새 이름에 대한 결정:** 이 티켓이 이음새에 판정 메서드를 추가한다. 이름은 Windows 어휘(`schemeRegistered(String)`)가 아니라 **플랫폼 중립적인 `canOpen(Uri)`**로 한다. macOS는 "스킴이 등록됐나"가 아니라 "이 URL을 열 앱이 있나"를 묻기 때문에(05 참조), Windows 어휘로 이름 지으면 05에서 이름과 의미가 어긋난다. Windows 구현이 내부적으로 스킴을 뽑아 레지스트리를 조회한다.

**Blocked by:** 01

**Status:** done — gates green, cross-read against a second reader

- [x] `bool canLaunchUrlSync(Uri)`와 `Future<bool> canLaunchUrl(Uri)`가 모두 공개 API로 존재하고 동작이 같다
- [x] `https://` URL에 대해 `true`를 반환한다
- [x] 설치되지 않은 앱의 커스텀 스킴에 대해 `false`를 반환한다
- [x] 존재하지 않는 스킴에 대해 `false`를 반환한다
- [x] 이음새의 판정 메서드가 `canOpen(Uri)` 형태로 플랫폼 중립적이다
- [x] 레지스트리 핸들이 모든 경로(성공·실패·예외)에서 닫힌다
- [x] 실제 레지스트리를 상대로 하는 통합 테스트가 존재하며, 아무 앱도 실행하지 않는다
- [x] Fake 이음새 주입 단위 테스트가 true/false 경로를 덮는다
