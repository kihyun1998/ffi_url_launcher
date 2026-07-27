# 04 — macOS에서 URL이 실제로 열린다

> **GitHub issue: #4** — the working surface. This file is the long-form
> design record; the issue carries state, labels and blocking edges.

**What to build:** macOS에서 `launchUrl`이 기본 브라우저를 실제로 띄운다. 동시에 플랫폼 분기가 실체화되면서, 지원하지 않는 OS에서 호출하면 조용히 실패하는 대신 명확한 `UnsupportedError`가 난다.

**설계 배경**

`package:objective_c` + ffigen을 **쓰지 않는다.** 그 패키지는 `hooks`/`code_assets`로 빌드 타임에 네이티브 코드를 컴파일하는데, 그러면 이 패키지를 쓰는 CLI 개발자가 `dart compile exe`를 못 쓰게 된다:

```
$ dart compile exe bin/main.dart
'dart compile' does not support build hooks, use 'dart build' instead.
```

대안인 `dart build cli`는 preview 단계이고 단일 실행파일이 아니라 번들 디렉터리를 내놓는다. CLI 개발자를 타겟으로 하는 패키지에서 이건 받아들일 수 없는 대가다.

LaunchServices C API(`LSOpenCFURLRef`, `LSCopyDefaultApplicationURLForURL`)도 쓰지 않는다. 순수 C ABI라 제일 쉽지만 각각 macOS 10.15, 12.0에서 deprecated 됐다 — 표면 전체가 deprecated인 기반 위에 공개 패키지를 올리는 건 부채다.

대신 `dart:ffi`로 Objective-C 런타임을 직접 부른다. `DynamicLibrary.open`은 런타임 dlopen이라 빌드 훅이 필요 없고, 그래서 `dart compile exe`가 그대로 살아있다:

```
/usr/lib/libobjc.A.dylib                          → objc_getClass, sel_registerName, objc_msgSend
/System/Library/Frameworks/AppKit.framework/AppKit → NSWorkspace 심볼 로드
```

호출 경로는 `[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:str]]` 한 줄기다.

**주의:** `NSWorkspace`는 메인 스레드 호출이 권장된다. FFI 호출은 동기이므로 호출한 아이솔레이트에서 그대로 실행된다 — `Isolate.run`으로 옮기지 말 것. (Windows의 `ShellExecuteW`도 엔진이 초기화한 COM 아파트먼트에 의존하므로 같은 제약이다. 이것이 이 패키지가 진짜 비동기를 제공하지 않는 이유다.)

`objc_msgSend`는 호출부마다 정확한 시그니처로 선언해야 한다. 반환 타입이 다른 호출을 하나의 선언으로 돌려쓰면 arm64에서 조용히 깨진다.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] 예제를 macOS에서 실행하면 기본 브라우저가 열린다
- [ ] `launchUrlSync` / `launchUrl` 모두 macOS에서 동작하며 Windows와 동일한 반환 규약을 따른다 (성공 `true`, 열 앱 없음 `false`)
- [ ] macOS에서 던져지는 `UrlLaunchException`의 `platformCode`는 `null`이다 (`NSWorkspace.open`은 BOOL만 반환하므로 담을 코드가 없다)
- [ ] `NSURL` 생성이 실패하는(nil) 입력에 대한 동작이 정해져 있고 테스트로 고정된다
- [ ] Windows·macOS가 아닌 플랫폼에서 공개 API를 호출하면 `UnsupportedError`가 난다
- [ ] `objc_msgSend`가 반환 타입별로 각각 선언되어 있고, 서로 다른 시그니처를 한 선언으로 돌려쓰지 않는다
- [ ] 반복 호출(수백 회)에서 autorelease 객체가 누적되지 않음을 확인한다
- [ ] `dart compile exe`가 이 패키지를 의존하는 프로젝트에서 성공한다 (06에서 CI로 고정하기 전, 로컬에서 최소 1회 확인)
