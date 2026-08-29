// 상태 갤러리(states) + 앱 크롬/메뉴 명세(app-chrome) 페이지.
// build.mjs가 공통 컴포넌트를 주입해 호출한다.
export function makeExtraPages(h) {
  const { page, IDX, SES, MODE } = h;
  const out = {};

  const sb = (inner) => `<div class="sb-demo">${inner}</div>`;
  const dot = h.dot;

  // ── states.html ────────────────────────────────────────────────────
  out['states'] = page({
    title: '상태 갤러리 — 인덱스·편집 세션·모드·빈/에러 상태',
    theme: 'dark',
    body: `<div class="gallery">
  <h1>code-navigator-mac — 상태 갤러리</h1>
  <p class="lead">02_design.md §3의 모든 상태를 한 장에 모은 시각 기준물. 프론트는 이 렌더를 타깃으로 구현하고, QA는 실제 앱을 이것과 대조한다.</p>

  <h2>1. 인덱스 상태 (§6 전이표 1:1 — 상태바 우측)</h2>
  <div class="grid">
    <div class="spec"><div class="cap"><b>없음</b> — 열린 프로젝트 없음</div>${IDX.none}</div>
    <div class="spec"><div class="cap"><b>인덱싱 중</b> — 프로젝트 열기 직후(진행률)</div>${IDX.indexing}</div>
    <div class="spec"><div class="cap"><b>최신</b> — 조회 결과가 소스와 일치(INV-1)</div>${IDX.ready}</div>
    <div class="spec"><div class="cap"><b>갱신 중</b> — 단일 파일 증분(저장·외부 변경)</div>${IDX.updating}</div>
    <div class="spec"><div class="cap"><b>전체 재스캔</b> — 대량 변경 폴백(git checkout)</div>${IDX.rescan}</div>
    <div class="spec"><div class="cap"><b>상세 팝오버</b> — 인덱스 칩 클릭</div>
      <div class="popover" style="position:static;width:auto">
        <div class="pop-head">인덱스 <b>최신</b></div>
        <div class="pop-item"><span>마지막 갱신</span><span class="loc">09:41:12</span></div>
        <div class="pop-item"><span>파일 · 심볼</span><span class="loc">4,812 · 38,204</span></div>
        <div class="pop-item"><span>스킵</span><span class="loc">3건 (파싱 실패 — 로그 기록)</span></div>
        <div class="pop-foot"><span>모든 비-최신 상태: 직전 인덱스로 응답</span></div>
      </div>
    </div>
  </div>

  <h2>2. 편집 세션 상태 (§6 전이표 1:1)</h2>
  <div class="grid">
    <div class="spec"><div class="cap"><b>미기동</b> — 앱 시작 직전</div><span class="chip"><i class="dot dot-none"></i>편집 세션 미기동</span></div>
    <div class="spec"><div class="cap"><b>연결 중</b> — nvim --embed 기동·RPC 연결</div>${SES.connecting}</div>
    <div class="spec"><div class="cap"><b>연결됨</b> — 정상 편집 가능</div>${SES.connected}</div>
    <div class="spec"><div class="cap"><b>끊김</b> — 프로세스 종료 감지(SC-7)</div>${SES.lost}</div>
  </div>
  <div class="grid" style="margin-top:12px">
    <div class="spec"><div class="cap"><b>연결 중</b> 에디터 영역</div>
      <div class="state-card" style="box-shadow:none">
        <span class="glyph">⏳</span><h2>편집 세션 연결 중…</h2>
        <p>Neovim을 기동하고 RPC로 연결하고 있습니다.</p>
        <p class="hint">연결 전 키 입력은 전달되지 않습니다(입력 유실 방지).</p>
      </div>
    </div>
    <div class="spec"><div class="cap"><b>기동 실패</b> — Neovim 미설치/버전 미달 (REQ-004 AC-1 · REQ-NF-005)</div>
      <div class="state-card" style="box-shadow:none">
        <span class="glyph">🚫</span><h2>Neovim을 찾을 수 없습니다</h2>
        <p>편집에는 Neovim이 필요합니다. 설치 후 다시 확인하세요.</p>
        <p class="hint">설치: <code>brew install neovim</code> · 필요 버전 {최소버전} 이상<br>탐색 경로: <code>/opt/homebrew/bin/nvim</code>, <code>/usr/local/bin/nvim</code>, <code>$PATH</code></p>
        <div class="actions"><button class="btn-primary">다시 확인</button><button class="btn-ghost">읽기 전용으로 계속</button></div>
      </div>
    </div>
    <div class="spec"><div class="cap"><b>끊김</b> 에디터 영역 (편집 UI 비활성)</div>
      <div class="state-card" style="box-shadow:none">
        <span class="glyph">⚠️</span><h2>편집 세션이 끊겼습니다</h2>
        <p>Neovim 프로세스가 종료되어 키 입력이 전달되지 않습니다.</p>
        <p class="hint">트리·심볼 검색·참조·전문 검색은 계속 사용할 수 있습니다.</p>
        <div class="actions"><button class="btn-primary">편집 세션 재기동 ⌃⌘R</button></div>
      </div>
    </div>
  </div>

  <h2>3. 입력 모드 표시 (REQ-010 AC-3 — 상태바 좌측, 항상 표시)</h2>
  <div class="grid">
    <div class="spec"><div class="cap"><b>Vim 모드</b> — Neovim 내부 모드를 그대로 반영</div>
      ${sb(MODE.normal)}<div style="height:6px"></div>${sb(MODE.insert)}<div style="height:6px"></div>${sb(MODE.visual)}<div style="height:6px"></div>${sb(MODE.command)}
    </div>
    <div class="spec"><div class="cap"><b>표준 모드</b> — 모드 개념 없음(하위 모드 미표시)</div>${sb(MODE.standard)}
      <div class="cap" style="margin-top:8px">전환은 <b>⌃⌘V</b> 또는 편집 ▸ 입력 모드. 전환만으로 저장되지 않음(AC-4)</div>
    </div>
    <div class="spec"><div class="cap"><b>편집 불가</b> — 편집 세션 끊김·연결 중</div>${sb(MODE.off)}</div>
  </div>

  <h2>4. 상태바 전체 (모드별 힌트 차이 · 더티 · 전이 메시지)</h2>
  <div class="grid">
    <div class="spec wide"><div class="cap"><b>Vim 모드 · 클린 버퍼 · 인덱스 최신</b></div>
      ${sb(`${MODE.normal}<span class="sb-sep"></span><span class="sb-path">Sources/Index/<b>SymbolIndex.swift</b></span><span class="sb-center"><span class="sb-hint">:w 저장 · gd 정의 이동 · ⌃O 뒤로</span></span>${IDX.ready}${SES.connected}`)}
    </div>
    <div class="spec wide"><div class="cap"><b>표준 모드 · 더티 버퍼(●) · 갱신 중</b></div>
      ${sb(`${MODE.standard}<span class="sb-sep"></span><span class="sb-path">Sources/Index/<b>SymbolIndex.swift</b></span>${dot}<span class="sb-center"><span class="sb-hint">⌘S 저장 · ⌘B 정의 이동 · ⌘[ 뒤로</span></span>${IDX.updating}${SES.connected}`)}
    </div>
    <div class="spec wide"><div class="cap"><b>저장 직후</b> — 더티 해제 + 메시지 2초 + 인덱스 갱신 중 전이 (SC-3)</div>
      ${sb(`${MODE.normal}<span class="sb-sep"></span><span class="sb-path">Sources/Index/<b>SymbolIndex.swift</b></span><span class="sb-center"><span class="sb-msg ok">✓ 저장됨 · SymbolIndex.swift (24줄, 1.1 KB)</span></span>${IDX.updating}${SES.connected}`)}
    </div>
    <div class="spec wide"><div class="cap"><b>정의 미발견</b> — 무반응 금지(REQ-005 AC-3), 3초 후 힌트로 복귀</div>
      ${sb(`${MODE.normal}<span class="sb-sep"></span><span class="sb-path">Sources/<b>App.swift</b></span><span class="sb-center"><span class="sb-msg err">✕ 'legacyScan' 정의를 찾을 수 없습니다</span></span>${IDX.ready}${SES.connected}`)}
    </div>
    <div class="spec wide"><div class="cap"><b>작은 창(&lt;900px)</b> — 힌트 숨김 · 경로 말줄임</div>
      <div class="sb-demo" style="max-width:420px">${MODE.normal}<span class="sb-sep"></span><span class="sb-path">…/Index/<b>SymbolIndex.swift</b></span><span class="sb-center"></span>${IDX.ready}</div>
    </div>
  </div>

  <h2>5. 빈 상태 · 에러 상태</h2>
  <div class="grid">
    <div class="spec"><div class="cap"><b>참조 0건</b> (REQ-006 AC-4) — 근사 안내 배너는 유지</div>
      <div class="banner"><span class="ico">ⓘ</span>이름 기반 검색 — 동명 이의어가 포함될 수 있습니다</div>
      <div class="panel-empty">'legacyScan' 참조 없음</div>
    </div>
    <div class="spec"><div class="cap"><b>참조 패널 초기</b> — 심볼 미선택</div>
      <div class="panel-empty">심볼에 커서를 두고 <b>⇧⌘B</b>를 누르면<br>참조 목록이 여기에 표시됩니다</div>
    </div>
    <div class="spec"><div class="cap"><b>심볼 검색 0건</b> (REQ-007 AC-4)</div>
      <div class="modal" style="margin:0;width:auto;box-shadow:none">
        <div class="modal-input-wrap"><span class="ico">🔍</span><span class="modal-input">zzqq</span></div>
        <div class="modal-empty">결과 없음 — 다른 이름으로 검색해 보세요</div>
        <div class="modal-foot"><span><kbd>esc</kbd> 닫기</span></div>
      </div>
    </div>
    <div class="spec"><div class="cap"><b>전문 검색 정규식 에러</b> (REQ-008 AC-2 · SC-6) — 빈 결과로 위장 금지</div>
      <div class="search-row" style="padding-left:0;padding-right:0"><input class="input err" value="([unclosed"><button class="toggle on">.*</button></div>
      <div class="field-error" style="padding-left:0"><span>⚠</span><span>잘못된 정규식: 닫히지 않은 그룹 '(' — 위치 1</span></div>
      <div class="result-meta" style="padding-left:0">이전 결과 유지 (새 검색 미실행)</div>
    </div>
    <div class="spec"><div class="cap"><b>전문 검색 0건</b></div><div class="panel-empty">결과 없음</div></div>
    <div class="spec"><div class="cap"><b>결과 상한</b> (REQ-008 AC-4)</div>
      <div class="cap" style="margin-bottom:6px">500건 표시 · 4,812 파일 검색 · 0.8초</div>
      <div class="cap-bar" style="margin-left:0;margin-right:0">상위 500건만 표시합니다 — 검색어를 더 구체적으로 좁혀 주세요</div>
    </div>
    <div class="spec"><div class="cap"><b>트리 로딩</b> — 프로젝트 전환 직후</div>
      <div style="background:var(--bg-sidebar);border-radius:6px;padding:8px 0">${'<div class="skel"></div>'.repeat(6)}</div>
    </div>
    <div class="spec"><div class="cap"><b>프로젝트 열기 실패</b> (REQ-001 AC-3) — 시트, 이전 상태 유지</div>
      <div class="sheet" style="width:auto;margin:0;border-radius:8px;border-top:1px solid var(--border);box-shadow:none">
        <span class="glyph">📁</span>
        <h2>프로젝트를 열 수 없습니다</h2>
        <p>경로를 찾을 수 없습니다: /Users/skull/repo/gone</p>
        <div class="actions"><button class="btn-primary">확인</button></div>
      </div>
    </div>
    <div class="spec"><div class="cap"><b>접근 권한 없음</b> (REQ-001 AC-3)</div>
      <div class="sheet" style="width:auto;margin:0;border-radius:8px;border-top:1px solid var(--border);box-shadow:none">
        <span class="glyph">🔒</span>
        <h2>프로젝트를 열 수 없습니다</h2>
        <p>폴더에 접근할 권한이 없습니다: /Users/other/private</p>
        <div class="actions"><button class="btn-primary">확인</button></div>
      </div>
    </div>
  </div>

  <h2>6. 심볼 종류 배지 (REQ-002 추출 종류의 UI 표면)</h2>
  <div class="grid">
    <div class="spec"><div class="cap">클래스 · 인터페이스 · enum · object · 함수/메서드 · 프로퍼티/필드 · 타입 별칭</div>
      <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;font-size:12px;color:var(--text-2)">
        <span><span class="kind kind-C">C</span> 클래스</span><span><span class="kind kind-I">I</span> 인터페이스</span>
        <span><span class="kind kind-E">E</span> enum</span><span><span class="kind kind-O">O</span> object</span>
        <span><span class="kind kind-F">F</span> 함수/메서드</span><span><span class="kind kind-P">P</span> 프로퍼티/필드</span>
        <span><span class="kind kind-T">T</span> 타입 별칭</span>
      </div>
    </div>
  </div>

  <h2>7. 테마 — 시스템 설정 추종 (REQ-011 AC-4)</h2>
  <div class="theme-pair">
    <div class="theme-box" data-theme="light">
      <div class="cap" style="font-size:11px;color:var(--text-3);margin-bottom:8px">라이트</div>
      ${sb(`${MODE.normal}<span class="sb-sep"></span><span class="sb-path">Sources/Index/<b>SymbolIndex.swift</b></span>${dot}<span class="sb-center"></span>${IDX.ready}`)}
      <div style="height:8px"></div>
      <div class="banner"><span class="ico">ⓘ</span>이름 기반 검색 — 동명 이의어가 포함될 수 있습니다</div>
      <div style="display:flex;gap:8px;margin-top:8px"><button class="btn-primary">프로젝트 열기…</button><button class="btn-ghost">취소</button></div>
    </div>
    <div class="theme-box" data-theme="dark">
      <div class="cap" style="font-size:11px;color:var(--text-3);margin-bottom:8px">다크</div>
      ${sb(`${MODE.normal}<span class="sb-sep"></span><span class="sb-path">Sources/Index/<b>SymbolIndex.swift</b></span>${dot}<span class="sb-center"></span>${IDX.ready}`)}
      <div style="height:8px"></div>
      <div class="banner"><span class="ico">ⓘ</span>이름 기반 검색 — 동명 이의어가 포함될 수 있습니다</div>
      <div style="display:flex;gap:8px;margin-top:8px"><button class="btn-primary">프로젝트 열기…</button><button class="btn-ghost">취소</button></div>
    </div>
  </div>
</div>`,
  });

  // ── app-chrome.html ────────────────────────────────────────────────
  const row = (label, sc = '', cls = '', check = '') =>
    `        <div class="menu-row ${cls}"><span class="check">${check}</span>${label}<span class="sc">${sc}</span></div>`;
  const div = `        <div class="menu-div"></div>`;
  out['app-chrome'] = page({
    title: '앱 크롬 — 메뉴 막대 · 단축키 · 창 규칙',
    theme: 'light',
    body: `<div class="desk">
  <div class="menubar">
    <span class="apple"></span><span class="mb-app">code-navigator-mac</span>
    <span>파일</span><span>편집</span><span>이동</span><span>보기</span><span>창</span><span>도움말</span>
  </div>

  <div class="menu-cards">
    <div class="menu-card">
      <div class="mc-title">파일</div>
${row('프로젝트 열기…', '⌘O')}
${row('최근 프로젝트 열기 ▸', '')}
${row('프로젝트 닫기', '⇧⌘W')}
${div}
${row('저장', '⌘S')}
${div}
${row('창 닫기', '⌘W')}
    </div>

    <div class="menu-card">
      <div class="mc-title">편집 — Vim 모드일 때</div>
${row('실행 취소', '⌘Z', 'disabled')}
${row('다시 실행', '⇧⌘Z', 'disabled')}
${row('오려두기 / 복사 / 붙여넣기', '⌘X ⌘C ⌘V', 'disabled')}
${div}
${row('입력 모드 전환', '⌃⌘V')}
${row('Vim 모드', '', '', '✓')}
${row('표준 모드', '')}
${div}
${row('편집 세션 재기동', '⌃⌘R')}
    </div>

    <div class="menu-card">
      <div class="mc-title">편집 — 표준 모드일 때</div>
${row('실행 취소', '⌘Z')}
${row('다시 실행', '⇧⌘Z')}
${row('오려두기 / 복사 / 붙여넣기', '⌘X ⌘C ⌘V')}
${row('전체 선택', '⌘A')}
${div}
${row('입력 모드 전환', '⌃⌘V')}
${row('Vim 모드', '')}
${row('표준 모드', '', '', '✓')}
    </div>

    <div class="menu-card">
      <div class="mc-title">이동</div>
${row('심볼 검색…', '⌘P')}
${row('전문 검색…', '⇧⌘F')}
${div}
${row('정의로 이동', '⌘B')}
${row('참조 보기', '⇧⌘B')}
${div}
${row('뒤로', '⌘[')}
${row('앞으로', '⌘]')}
    </div>

    <div class="menu-card">
      <div class="mc-title">보기</div>
${row('파일 트리 표시', '⌥⌘1', '', '✓')}
${row('참조·검색 패널 표시', '⌥⌘0', '', '✓')}
${div}
${row('전체 화면 시작', '⌃⌘F')}
    </div>

    <div class="menu-card">
      <div class="mc-title">창 / 도움말</div>
${row('최소화', '⌘M')}
${row('확대', '')}
${div}
${row('code-navigator-mac 도움말', '')}
    </div>
  </div>

  <div class="chrome-note">
    <h2>단축키 규칙 — Neovim 입력과 충돌 금지 (REQ-011 AC-2 · REQ-010 AC-5)</h2>
    <ul>
      <li><b>앱은 ⌘를 포함한 조합만 가로챈다.</b> ⌃ 단독 조합(⌃O·⌃R·⌃V·⌃W…)과 모든 일반 키는 가공 없이 Neovim으로 전달된다.</li>
      <li>Vim 모드에서도 위 ⌘ 단축키는 계속 동작한다(REQ-010 AC-5). 반대로 표준 모드에서 <code>hjkl</code>·<code>:</code>·<code>i</code>는 일반 문자로 입력된다.</li>
      <li>편집 메뉴의 텍스트 편집 항목(⌘Z·⌘C·⌘V·⌘A)은 <b>표준 모드에서만 활성</b>이다. Vim 모드에서는 <code>u</code>·<code>y</code>·<code>p</code>가 그 역할이며, 두 경로가 섞이면 undo 이력이 갈린다.</li>
      <li>⌘S(저장)는 두 모드 모두 활성 — 저장은 앱 수준 동작이고, 실제 쓰기는 Neovim <code>:w</code>로 위임된다(INV-3).</li>
      <li>입력 모드 토글은 <b>메뉴 항목 + 단축키(⌃⌘V)</b> 두 수단을 모두 제공한다(REQ-010 AC-3). 툴바 세그먼트는 발견성 보강용 선택 구현.</li>
    </ul>
  </div>

  <div class="chrome-note">
    <h2>창 규칙 (REQ-011 AC-1 · AC-3)</h2>
    <ul>
      <li>표준 맥 창: 리사이즈 · 최소화 · 전체화면. 통합 툴바(높이 48px) + 하단 상태바(높이 26px).</li>
      <li>최소 창 크기 <b>720×480</b>. 기본 창 <b>1280×800</b>.</li>
      <li>재시작 시 복원: 창 크기·위치, 트리/패널 표시 여부와 분할 비율, 최근 프로젝트, 입력 모드(REQ-010 AC-6).</li>
      <li>레이아웃 적응: 창 폭 ≥900px = 3영역 동시 표시(트리 240 · 에디터 ≥420 · 패널 340) / &lt;900px = 패널이 에디터 위 우측 오버레이(320px) / &lt;720px = 트리도 오버레이.</li>
      <li>제목: 열린 파일 이름 + 더티 버퍼 표시(●). 파일 없으면 프로젝트 이름.</li>
    </ul>
  </div>

  <div class="mini-window">
    <div class="app" style="height:220px">
      <header class="titlebar">
        <div class="lights"><span class="light l-close"></span><span class="light l-min"></span><span class="light l-max"></span></div>
        <div class="win-title">SymbolIndex.swift <span class="dirty-dot"></span></div>
        <div class="tb-group"><button class="tb-btn wide">📁 code-navigator-mac <span class="caret">▾</span></button></div>
        <div class="tb-spacer"></div>
        <div class="tb-group">
          <div class="seg"><button class="on">Vim</button><button>표준</button></div>
          <button class="tb-btn"><span class="ico">🔍</span>심볼<kbd>⌘P</kbd></button>
          <button class="tb-btn"><span class="ico">☰</span>전문 검색<kbd>⇧⌘F</kbd></button>
        </div>
      </header>
      <div class="body no-panel" style="grid-template-columns:minmax(0,1fr)">
        <div class="editor"><div class="editor-note"><div style="color:var(--text-3);font-size:12px;text-align:center">
          통합 툴바 48px · 상태바 26px · 트래픽 라이트 좌측 · 제목 중앙(더티 ● 표시)<br>에디터 영역은 Neovim이 그린다
        </div></div></div>
      </div>
      <footer class="statusbar">
        <div class="sb-left"><span class="mode-chip mode-normal">NORMAL</span><span class="mode-layer">Vim</span><span class="sb-sep"></span><span class="sb-path">Sources/Index/<b>SymbolIndex.swift</b></span><span class="dirty-dot"></span></div>
        <div class="sb-center"><span class="sb-hint">:w 저장 · gd 정의 이동 · ⌃O 뒤로</span></div>
        <div class="sb-right"><span>8:5</span><span class="sb-sep"></span><span>Swift</span>${IDX.ready}${SES.connected}</div>
      </footer>
    </div>
  </div>
</div>`,
  });

  return out;
}
