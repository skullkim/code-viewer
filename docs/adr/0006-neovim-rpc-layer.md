# 0006. Neovim RPC 계층 — 자체 MessagePack + `--embed`

- 상태: 채택
- 날짜: 2026-08-29
- 결정자: backend-senior

## 맥락
REQ-004는 편집기를 자체 구현하지 않고 **임베드된 Neovim 프로세스**에 위임한다. 앱은
msgpack-RPC로 연결해 키를 넘기고 화면을 받아 그린다. INV-3(편집 단일 경로)와 INV-4(설정 비침범)가
여기에 걸려 있고, REQ-005(정의 이동·점프 목록)·REQ-009 AC-5(저장 후 재인덱싱)·REQ-010(입력 모드 토글)이
전부 이 계층 위에 선다. 착수 전 실측이 필요한 최대 리스크였다.

## 결정
- Neovim을 `--embed`로 기동하고 stdin/stdout을 msgpack-RPC 채널로 쓴다.
- **MessagePack 코덱과 RPC 클라이언트를 직접 구현한다.** 외부 패키지를 쓰지 않는다.
- UI는 `nvim_ui_attach`로 붙이고 `ext_linegrid` redraw 이벤트를 받아 **엔진이 그리드 상태를
  유지**한 뒤, `flush`마다 완성된 `EditorGridSnapshot`을 프론트엔드에 넘긴다(ADR-0001).
- 저장 감지는 파일 감시에 맡기지 않고, `BufWritePost` autocmd가 `vim.rpcnotify`로 저장된
  경로를 직접 통지하게 한다.
- 사용자 설정은 건드리지 않는다. `--clean`을 **쓰지 않으며** `~/.config/nvim`을 읽지도 쓰지도 않는다.

## 실측 (spike, 2026-08-29 — Neovim 0.12.5)
| 검증 항목 | 결과 |
|---|---|
| 요청/응답 (`nvim_eval("1+1")`) | `2` — 왕복 정상 |
| 에러 응답 (없는 메서드) | `Invalid method: …`가 실패로 표면화 (조용한 실패 없음) |
| `nvim_ui_attach` 후 redraw | 17종 이벤트 수신: `grid_resize` `grid_line` `grid_clear` `grid_cursor_goto` `mode_change` `hl_attr_define` `default_colors_set` `flush` 등 — 렌더에 필요한 것 전부 |
| 키 입력 → 버퍼 | `nvim_input("ihello…")` 후 버퍼 내용·모드 전이(`normal→insert→normal`) 확인 |
| 더티 상태 | 편집 후 `modified=true`, `:w` 후 `false` |
| INV-3 | 버퍼를 고쳐도 디스크에 파일이 **생기지 않음**. `:w` 시점에만 생성됨 — 쓰기 경로가 하나임을 실증 |
| `BufWritePost` → `rpcnotify` | 저장된 절대 경로가 앱으로 도착 |
| 커서·`<cword>`·점프 목록 | `nvim_win_get_cursor`, `expand('<cword>')`, `getjumplist()` 정상 |
| 프로세스 강제 종료(SIGKILL) | `terminationHandler` 발화 + 이후 요청이 즉시 실패 → 감지 가능 |
| 사용자 설정 적용 | init.lua의 옵션·유저 커맨드·키맵이 모두 적용됨 |

### spike가 드러낸 결정적 사실 두 가지
1. **`--embed` 단독이면 UI가 붙을 때까지 시동이 멈춘다.** `nvim_ui_attach` 전에는 사용자
   `init.lua`가 **아직 실행되지 않는다**(실측: attach 전 `false`, attach 후 `true`).
   따라서 기동 순서는 `spawn → ui_attach → 설정 로드 완료`이며, 설정 의존 질의는 attach 이후에 한다.
   attach까지 포함한 첫 응답이 519ms로 REQ-NF-003(≤2초) 안쪽이다.
2. **`nvim_ui_attach`는 렌더링뿐 아니라 입력의 전제조건이다.** attach 전에 보낸 `nvim_input`은
   **조용히 아무 일도 하지 않는다**(통합 테스트로 고정). 위 1번과 같은 뿌리 — 시동이 멈춰 있기 때문이다.
   따라서 세션의 기동 순서는 `spawn → ui_attach → (설정 로드 완료) → 입력 수용`으로 고정이며,
   그 전에 도착한 사용자 키는 버리지 말고 큐에 담았다가 attach 후 흘려보낸다.
3. **`SIGPIPE`를 무시하지 않으면 앱이 죽는다.** Neovim이 사라진 뒤 stdin에 쓰면 기본 동작이
   프로세스 종료다. spike 첫 실행이 정확히 이렇게 죽었고(exit 141), 출력조차 남기지 못했다.
   `signal(SIGPIPE, SIG_IGN)` 후에는 쓰기가 `EPIPE` 에러로 돌아와 정상적으로 처리된다.
   REQ-004 AC-5·SC-7("조용한 먹통 금지")이 이 한 줄에 달려 있다.

## 고려한 대안
1. **기존 Swift msgpack 패키지 + 자체 RPC** — 코덱을 안 짜도 된다. 그러나 우리가 필요한 것은
   msgpack 전체가 아니라 Neovim이 실제로 쓰는 타입 집합이고, RPC 프레이밍·요청 상관·알림 분배는
   어차피 직접 짜야 한다. 의존성을 하나 늘려 얻는 것이 코덱 200줄뿐이다.
2. **기존 Swift Neovim 클라이언트 패키지** — 가장 많이 얻는 선택. 그러나 이 계층은 앱의 심장이고
   (INV-3·INV-4·REQ-004/005/009/010이 전부 여기 걸림), 유지보수 상태가 불확실한 서드파티에
   심장을 맡기면 디버깅이 남의 코드로 새어나간다. spike로 필요한 API 표면이 좁다는 것을 확인했다.
3. **자체 구현 (채택)** — 코덱은 순수 함수라 테스트가 쉽고(바이트 배열 in/out), 프로세스 수명·
   재기동·에러 표면화를 우리 요구사항에 맞게 정확히 설계할 수 있다.

## 트레이드오프
- 얻는 것: 의존성 0, 전 계층 테스트 가능, 실패 모드를 우리가 정의(REQ-004 AC-1/AC-5의 "명확한 안내").
- 잃는 것: MessagePack 스펙을 우리가 책임진다. Neovim이 보내는 타입(정수 전 폭·str/bin·array·map·
  ext·float)을 빠짐없이 디코드해야 하며, 빠뜨리면 런타임에 드러난다 → 코덱 단위 테스트로 고정한다.
- 되돌리기: `EditorSession` 프로토콜 뒤에 있으므로 구현 교체는 국소적이다.

## 결과 (구현 시 반드시 지킬 것)
- `signal(SIGPIPE, SIG_IGN)`을 앱 기동 시 1회 호출한다.
- stdout 수신은 **부분 프레임을 견뎌야 한다**. 버퍼에 누적하고, 디코드에 실패하면 더 올 때까지
  기다린다(파이프는 msgpack 프레임 경계에서 잘려 오지 않는다).
- 응답 대기 핸들러는 락 밖에서 호출한다(디코드 중 재진입 방지).
- 정의 이동 전에는 `normal! m'`로 점프 목록에 현재 위치를 남긴다(REQ-005 AC-4).
- `--clean`은 테스트 격리용으로만 쓴다. 프로덕션 기동에는 절대 붙이지 않는다(INV-4).
  설정 충실도 테스트는 `XDG_CONFIG_HOME`을 픽스처로 주입해 검증한다 — 사용자 홈을 건드리지 않는다.
