# 02 — 안전하지 않은 URL이 거부된다

**What to build:** 로컬 실행파일 경로를 URL인 척 넘겨 임의 실행을 유도하는 경로를 기본값에서 막는다. 막힌 호출은 조용히 실패하지 않고 전용 예외로 알린다. 이 방어가 방해가 되는 호출자는 명시적으로 끌 수 있다.

**설계 배경**

`Uri` 타입을 받는 것만으로는 안전하지 않다. Dart의 `Uri` 파서는 Windows 드라이브 문자를 스킴으로 읽는다:

```
Uri.parse(r'C:\Windows\System32\calc.exe')
  → scheme = 'c',  hasScheme = true,  toString() = 'c:/Windows/System32/calc.exe'
```

`ShellExecuteW`는 정슬래시 경로를 받아들이므로 이 값이 그대로 `calc.exe`를 **실행**한다. 즉 `hasScheme` 검사만으로는 뚫린다. 실제로 막히는 조합은 두 검사를 함께 걸었을 때다:

| 입력 | 판정 근거 |
|---|---|
| `C:\Windows\System32\calc.exe` | 스킴 길이 1 → 드라이브 문자 |
| `\\attacker\share\evil.exe` | 스킴 없음 |
| `evil.bat` | 스킴 없음 |
| `''` (빈 문자열) | 스킴 없음 |

> **실측 근거 추가 (티켓 01 구현 중).** 마지막 행은 가상의 위협이 아니다. Windows 11에서 `ShellExecuteW('')`를 부르면 **탐색기 창이 열리고 42(성공)를 반환한다** — 화면에서 확인함. 즉 지금 `launchUrlSync(Uri.parse(''))`는 엉뚱한 창을 띄우고 `true`를 돌려준다. 설정 파일의 빈 값이나 치환되지 않은 템플릿 변수가 흘러들면 그대로 재현된다. 이 티켓의 `hasScheme` 필수 검사가 정확히 이걸 막는다. 근거: `docs/agents/lessons.md` #4.

RFC 3986상 1글자 스킴은 합법이지만 실제로 등록·사용되는 것이 없어, Windows에서 1글자 스킴은 사실상 드라이브 문자다.

**이 방어는 부분적이다.** `file:///C:/Windows/System32/calc.exe`는 모든 검사를 통과하고 실행된다. `file:`은 데스크톱에서 정당한 기능이라 막지 않는다. 그래서 "안전하다"가 아니라 **"이것만 막는다, 나머지는 호출자 책임"**을 문서에 명시하는 것이 설계의 일부다 (07에서 다룸). 부분 방어가 주는 거짓 안전감이 이 결정의 가장 큰 위험이다.

선례: `url_launcher_web`도 화이트리스트가 아닌 블록리스트(`_disallowedSchemes = {'javascript'}`)를 쓴다. flutter/flutter#136657에서 P1으로 신고돼 수정된 건이다.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] 스킴이 없는 URL(`evil.bat`, UNC 경로)을 넘기면 `UnsafeUrlError`가 던져진다
- [ ] 스킴 길이가 1인 URL(`C:\...`)을 넘기면 `UnsafeUrlError`가 던져진다
- [ ] `allowUnsafe: true`를 주면 위 두 경우 모두 검증을 건너뛰고 네이티브 호출까지 도달한다
- [ ] `file:`, `ms-settings:`, `mailto:`, 커스텀 스킴(`myapp://`)은 기본값에서 통과한다
- [ ] `UnsafeUrlError`는 `UrlLaunchException`과 구분되는 타입이라, 호출자가 "차단됨"과 "시스템 오류"를 catch로 구별할 수 있다
- [ ] 동일한 검증이 `launchUrl` 계열과 `canLaunchUrl` 계열에 모두 적용된다
- [ ] 검증은 플랫폼 무관 순수 로직이므로 이 테스트들이 어느 OS에서도 통과한다
