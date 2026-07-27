# 06 — CI가 Windows·macOS 양쪽에서 초록불이 된다

> **GitHub issue: #6** — the working surface. This file is the long-form
> design record; the issue carries state, labels and blocking edges.

**What to build:** PR을 올리면 실제 Windows와 실제 macOS에서 테스트가 돌아간다. 손으로 두 대의 머신을 오가며 확인하던 것이 자동화된다. 그리고 이 패키지의 핵심 설계 약속 — "빌드 훅 없이 `dart compile exe`가 된다" — 이 회귀하면 CI가 잡는다.

**설계 배경**

`launchUrl`은 실제로 브라우저를 여는 부작용이 있어 CI에서 그대로 돌릴 수 없다. 하지만 부작용 없이 실제 OS를 상대로 검증할 수 있는 것이 있다:

- `canLaunchUrl` — 레지스트리 읽기 / LaunchServices 조회뿐, 아무것도 실행하지 않는다
- **존재하지 않는 경로로 `launchUrl`** — 셸이 `SE_ERR_FNF`(2)로 즉시 거부하므로 UI가 뜨지 않고, 그러면서 라이브러리 로드 → UTF-16 마샬링 → 호출 → 코드 해석 → 예외 매핑 전체를 관통한다
- 검증 로직 — 플랫폼 무관 순수 로직

> ⚠ **정정 (티켓 01 구현 중 실측).** 이 자리에 원래 *"미등록 스킴으로 `launchUrl` → 아무 창도 안 뜨고 `false`"* 라고 적혀 있었는데 **거짓이다.** Windows 11에서 미등록 스킴은 `SE_ERR_NOASSOC`(31)이 아니라 **42(성공)** 를 반환하고, 셸이 자기 "앱을 어떻게 열까요?" UI를 띄운다. 그대로 CI에 넣었으면 거짓을 단언하면서 매 실행마다 대화상자를 띄웠을 것이다. 근거는 `docs/agents/lessons.md` #4.

CI가 지켜야 할 가장 중요한 것은 **의존성이 늘어나지 않는 것**이다. 누군가 편의를 위해 `package:win32`나 `package:objective_c`를 추가하는 순간 빌드 훅이 딸려오거나 플랫폼 태그가 어긋나는데, 이건 코드 리뷰로는 놓치기 쉽고 `dart compile exe` 잡이 있으면 즉시 잡힌다.

**Blocked by:** 05

05가 끝나야 두 플랫폼 모두 부작용 없는 통합 테스트를 갖게 되어, 매트릭스 양쪽 레그가 의미 있는 검증을 한다.

**Status:** ready-for-agent

- [ ] GitHub Actions 워크플로가 `windows-latest`와 `macos-latest` 매트릭스로 실행된다
- [ ] PR과 기본 브랜치 푸시 양쪽에서 자동 실행된다
- [ ] `dart analyze`가 경고 없이 통과하는 것을 검사한다
- [ ] `dart format --set-exit-if-changed`로 포맷을 강제한다
- [ ] `dart test`가 양쪽 OS에서 통과한다 (실제 브라우저를 여는 테스트는 포함하지 않는다)
- [ ] 이 패키지를 의존하는 최소 프로젝트에서 `dart compile exe`가 성공하는지 검사하는 잡이 있다 — 빌드 훅 의존성이 몰래 들어오는 것을 막는 가드
- [ ] 워크플로가 Flutter를 설치하지 않고 순수 Dart SDK만으로 돌아간다 — 이 패키지가 Flutter 없이 쓰인다는 약속의 실증
