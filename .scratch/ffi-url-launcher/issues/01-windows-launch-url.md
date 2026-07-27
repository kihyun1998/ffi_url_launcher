# 01 — Windows에서 URL이 실제로 열린다

**What to build:** Windows에서 `launchUrl(Uri.parse('https://example.com'))`을 부르면 기본 브라우저가 실제로 뜬다. 예제를 실행해 눈으로 확인할 수 있다. 열 앱이 없으면 `false`를 돌려주고, 그 외 시스템 오류는 플랫폼 에러 코드를 담은 예외로 알린다.

이 티켓이 트레이서 불릿이다 — 공개 API, 테스트 이음새, FFI 바인딩, 에러 매핑을 한 줄기로 관통한다. 현재 레포는 `dart create` 스캐폴딩(`Awesome` 클래스) 상태이므로 그 정리도 여기 포함된다.

**설계 배경**

- 이 패키지는 순수 Dart다. `flutter`에 의존하지 않으며 빌드 훅(`hooks`/`code_assets`)도 쓰지 않는다. 그래야 `dart pub get` → `dart run` → `dart compile exe`가 특별 처리 없이 동작하고, pub.dev에서 `sdk:dart`와 `sdk:flutter` 태그를 모두 받는다.
- Win32 바인딩은 `package:win32`를 쓰지 않고 직접 `lookupFunction` 한다. win32는 pubspec에 `platforms: windows:`를 선언한 Windows 전용 패키지라, macOS도 지원하는 이 패키지가 의존하면 플랫폼 태그가 어긋난다. 필요한 함수가 총 4개뿐이라 직접 선언하는 비용이 더 싸다.
- `ShellExecuteW`는 HINSTANCE 호환성 때문에 **성공 시 32보다 큰 값**을 반환한다. 32 이하가 전부 에러 코드다.

**Blocked by:** 없음 — 바로 시작 가능

**Status:** ready-for-agent

- [ ] 예제를 Windows에서 실행하면 기본 브라우저가 열린다
- [ ] `bool launchUrlSync(Uri)`와 `Future<bool> launchUrl(Uri)`가 모두 공개 API로 존재하고 동작이 같다 (비동기는 동기 호출을 즉시 완료되는 Future로 감쌈)
- [ ] 성공 시 `true`를 반환한다
- [ ] `SE_ERR_NOASSOC`(31, 이 URL을 열 앱이 없음)이면 예외 없이 `false`를 반환한다
- [ ] 그 외 32 이하 반환값이면 `UrlLaunchException`을 던진다. 예외는 `url`, `platformCode`(int?), `message`를 담는다
- [ ] 네이티브 호출이 주입 가능한 추상 이음새 뒤에 있고, ~~`@visibleForTesting` 생성자로만 교체 가능하며~~ 공개 API 표면에는 노출되지 않는다
- [ ] Fake 이음새를 주입한 단위 테스트가 에러 코드 매핑을 검증한다 (최소한 31 → `false`, 5 → throw, 33 → `true`)

> **정정 — 이 criterion은 쓰인 대로는 만족 불가능하다.** `@visibleForTesting`은 `package:meta`를 실제 의존성으로 요구하는데, 이 티켓의 다른 criterion(*"런타임 의존성이 `ffi` 하나뿐"*)과 정면으로 충돌한다. 둘 다 만족시킬 방법은 없다.
>
> 의존성 불변식이 이긴다 — 그게 `dart compile exe`를 지키는 조건이고, 형제 레포 `just_autostart`도 같은 상황에서 문서화된 `Autostart.withBackend` 공개 생성자로 해결했다. 대신 **이음새가 받는 타입을 export하지 않는 것**이 노출을 막는다: `UrlLauncherBackend`는 `lib/ffi_url_launcher.dart`에 없으므로 외부 코드가 `src/`를 파고들지 않고는 인자 타입을 이름 붙일 수 없다. 근거는 `docs/agents/theflow.md`의 모듈 맵 아래 주석.
- [ ] pubspec의 런타임 의존성이 `ffi` 하나뿐이고, `flutter` 의존이 없으며, 버전이 `0.1.0`이다
- [ ] 스캐폴딩 잔재(`Awesome` 클래스, 기본 예제, 기본 테스트)가 제거된다
- [ ] `dart analyze`가 경고 없이 통과한다
