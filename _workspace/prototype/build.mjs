// 프로토타입 페이지 생성기 — 공통 셸(타이틀바·트리·에디터·패널·상태바)을 재사용해
// 화면×상태 조합을 정적 HTML로 emit 한다. 생성물(*.html)이 시각 기준물이다.
// 사용: node build.mjs
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeExtraPages } from './pages-extra.mjs';

const ROOT = dirname(fileURLToPath(import.meta.url));
const dot = '<span class="dirty-dot" title="더티 버퍼 — 저장되지 않은 변경"></span>';

// ── 타이틀바(통합 툴바) ────────────────────────────────────────────────
function titlebar({ project = 'code-navigator-mac', file = null, dirty = false, mode = 'vim', panelOn = true, noProject = false } = {}) {
  const off = noProject ? ' disabled' : '';
  const title = file ? `${file}${dirty ? ' ' + dot : ''}` : project;
  return `  <header class="titlebar">
    <div class="lights"><span class="light l-close"></span><span class="light l-min"></span><span class="light l-max"></span></div>
    <div class="win-title">${title}</div>
    <div class="tb-group">
      <button class="tb-btn wide" aria-haspopup="menu">📁 <span class="lbl">${project}</span> <span class="caret">▾</span></button>
    </div>
    <div class="tb-spacer"></div>
    <div class="tb-group">
      <div class="seg" role="group" aria-label="입력 모드">
        <button class="${mode === 'vim' ? 'on' : ''}" aria-pressed="${mode === 'vim'}">Vim</button>
        <button class="${mode === 'standard' ? 'on' : ''}" aria-pressed="${mode === 'standard'}">표준</button>
      </div>
      <button class="tb-btn"${off}><span class="ico">🔍</span><span class="lbl">심볼</span><kbd>⌘P</kbd></button>
      <button class="tb-btn"${off}><span class="ico">☰</span><span class="lbl">전문 검색</span><kbd>⇧⌘F</kbd></button>
      <button class="tb-btn"${off} aria-pressed="${panelOn}"><span class="lbl">패널</span><kbd>⌥⌘0</kbd></button>
    </div>
  </header>`;
}

// ── 파일 트리 ─────────────────────────────────────────────────────────
function tree({ active = 'SymbolIndex.swift', dirty = false, loading = false } = {}) {
  if (loading) {
    return `    <nav class="tree" aria-label="파일 트리"><div class="tree-title">code-navigator-mac</div>
      ${'<div class="skel"></div>'.repeat(7)}</nav>`;
  }
  const rows = [
    ['', '▾', '📂', 'Sources', 0],
    ['d1', '▾', '📂', 'Index', 1],
    ['d2', '', '📄', 'SymbolIndex.swift', 2],
    ['d2', '', '📄', 'Parser.swift', 2],
    ['d2', '', '📄', 'Symbol.swift', 2],
    ['d1', '▸', '📂', 'Editor', 1],
    ['d1', '▸', '📂', 'Search', 1],
    ['d1', '', '📄', 'App.swift', 1],
    ['', '▸', '📂', 'Tests', 0],
    ['', '', '📄', 'Package.swift', 0],
    ['', '', '📄', 'README.md', 0],
  ];
  const items = rows.map(([cls, tw, ic, name]) => {
    const on = name === active;
    return `      <div class="tree-item ${cls}${on ? ' active' : ''}"><span class="tw">${tw}</span><span class="ic">${ic}</span>${name}${on && dirty ? dot : ''}</div>`;
  }).join('\n');
  return `    <nav class="tree" aria-label="파일 트리">
      <div class="tree-title">code-navigator-mac</div>
${items}
    </nav>`;
}

// ── 에디터(Neovim 렌더 영역) ───────────────────────────────────────────
const CODE = (hl, dirtyLine) => {
  const L = [
    [1, `<span class="k">import</span> Foundation`],
    [2, ''],
    [3, `<span class="c">/// 정방향·역방향 인덱스 — 소스에서 전량 재생성 가능한 파생물</span>`],
    [4, `<span class="k">final class</span> <span class="t">SymbolIndex</span> {`],
    [5, `    <span class="k">private var</span> byFile: [<span class="t">String</span>: [<span class="t">Symbol</span>]] = [:]`],
    [6, `    <span class="k">private var</span> byName: [<span class="t">String</span>: [<span class="t">Location</span>]] = [:]`],
    [7, ''],
    [8, `    <span class="k">func</span> <span class="f">buildIndex</span>(files: [<span class="t">URL</span>]) {`],
    [9, `        <span class="k">for</span> file <span class="k">in</span> files { <span class="f">indexFile</span>(file) }`],
    [10, `    }`],
    [11, ''],
    [12, `    <span class="k">func</span> <span class="f">indexFile</span>(<span class="k">_</span> url: <span class="t">URL</span>) {`],
    [13, `        <span class="f">removeFile</span>(url)  <span class="c">// 증분 갱신: 옛 심볼 제거 후 대체</span>`],
    [14, `        <span class="k">let</span> symbols = <span class="t">Parser</span>.<span class="f">parse</span>(url)`],
    [15, `        byFile[url.path] = symbols`],
    [16, `        <span class="k">for</span> symbol <span class="k">in</span> symbols {`],
    [17, `            byName[symbol.name, <span class="k">default</span>: []].<span class="f">append</span>(symbol.location)`],
    [18, `        }`],
    [19, `    }`],
    [20, ''],
    [21, `    <span class="k">func</span> <span class="f">definitions</span>(of name: <span class="t">String</span>) -> [<span class="t">Location</span>] {`],
    [22, `        byName[name] ?? []`],
    [23, `    }`],
    [24, `}`],
  ];
  if (dirtyLine) L.splice(19, 0, [null, dirtyLine]);
  let n = 0;
  return L.map(([ln, code]) => {
    n += 1;
    const num = ln === null ? n : n;
    const cls = num === hl ? ' hl' : '';
    return `        <div class="cl${cls}"><span class="ln">${num}</span><span class="lc">${code}</span></div>`;
  }).join('\n') + '\n        <div class="cl"><span class="ln tilde">~</span><span class="lc"></span></div>'.repeat(60);
};

function editor({ hl = 8, nvimMode = 'NORMAL', file = 'SymbolIndex.swift', dirty = false, dirtyLine = null, cmdline = '', overlay = '', popover = '', disabled = false } = {}) {
  const modeCls = nvimMode === 'INSERT' ? ' insert' : '';
  return `    <main class="editor" aria-label="에디터 — Neovim 렌더 영역">
      <!-- 이 영역의 텍스트·라인번호·구문강조·커서는 모두 Neovim이 그린다. 앱은 그리지 않는다. -->
      <div class="nvim${disabled ? ' dimmed' : ''}">
${CODE(hl, dirtyLine)}
      </div>
      <!-- 아래 상태줄은 사용자의 ~/.config/nvim 설정이 그린 Neovim 상태줄이다(앱 상태바와 별개, INV-4) -->
      <div class="nvim-status${disabled ? ' dimmed' : ''}">
        <span class="seg-mode${modeCls}">${nvimMode}</span>
        <span class="seg-file">${file}${dirty ? ' [+]' : ''}</span>
        <span class="seg-meta">swift  utf-8  LF</span>
        <span class="seg-pos">8:5  32%</span>
      </div>
      <div class="nvim-cmdline${disabled ? ' dimmed' : ''}">${cmdline}</div>
${popover}${overlay}
    </main>`;
}

// ── 우측 패널 ─────────────────────────────────────────────────────────
function panelRefs({ state = 'normal' } = {}) {
  const tabs = `      <div class="tabs" role="tablist"><button class="tab active" role="tab" aria-selected="true">참조</button><button class="tab" role="tab" aria-selected="false">검색</button></div>`;
  const banner = `      <div class="banner"><span class="ico">ⓘ</span>이름 기반 검색 — 동명 이의어가 포함될 수 있습니다</div>`;
  if (state === 'initial') {
    return `    <aside class="panel" aria-label="참조 패널">
${tabs}
      <div class="panel-empty">심볼에 커서를 두고 <b>⇧⌘B</b>를 누르면<br>참조 목록이 여기에 표시됩니다</div>
    </aside>`;
  }
  if (state === 'empty') {
    return `    <aside class="panel" aria-label="참조 패널">
${tabs}
      <div class="panel-head"><span class="panel-title">legacyScan</span><span class="panel-count">· 0건</span></div>
${banner}
      <div class="panel-empty">'legacyScan' 참조 없음</div>
    </aside>`;
  }
  return `    <aside class="panel" aria-label="참조 패널">
${tabs}
      <div class="panel-head"><span class="panel-title">buildIndex</span><span class="panel-count">· 5건 (정의 1)</span></div>
${banner}
      <div class="plist" role="listbox">
        <div class="pgroup">Sources/Index/SymbolIndex.swift</div>
        <div class="pitem active" role="option" aria-selected="true"><span class="loc">8</span><span class="def-badge">정의</span><span class="prev">func <mark>buildIndex</mark>(files: [URL]) {</span></div>
        <div class="pgroup">Sources/App.swift</div>
        <div class="pitem"><span class="loc">42</span><span class="prev">index.<mark>buildIndex</mark>(files: scanner.sourceFiles())</span></div>
        <div class="pitem"><span class="loc">96</span><span class="prev">index.<mark>buildIndex</mark>(files: changed)  // 전체 재스캔 폴백</span></div>
        <div class="pgroup">Tests/SymbolIndexTests.swift</div>
        <div class="pitem"><span class="loc">17</span><span class="prev">sut.<mark>buildIndex</mark>(files: fixtures)</span></div>
        <div class="pitem"><span class="loc">64</span><span class="prev">sut.<mark>buildIndex</mark>(files: [tmp])  // INV-1 회귀</span></div>
      </div>
    </aside>`;
}

function panelSearch({ state = 'normal' } = {}) {
  const tabs = `      <div class="tabs" role="tablist"><button class="tab" role="tab" aria-selected="false">참조</button><button class="tab active" role="tab" aria-selected="true">검색</button></div>`;
  const results = (dim) => `      <div class="plist${dim ? ' dimmed' : ''}" role="listbox">
        <div class="pgroup">Sources/Index/SymbolIndex.swift</div>
        <div class="pitem active"><span class="loc">13</span><span class="prev">removeFile(url)  // <mark>증분 갱신</mark>: 옛 심볼 제거 후 대체</span></div>
        <div class="pgroup">Sources/Index/Watcher.swift</div>
        <div class="pitem"><span class="loc">28</span><span class="prev">/// 디바운스 후 <mark>증분 갱신</mark>을 요청한다</span></div>
        <div class="pitem"><span class="loc">51</span><span class="prev">logger.debug("<mark>증분 갱신</mark> 시작 \\(path)")</span></div>
        <div class="pgroup">Sources/App.swift</div>
        <div class="pitem"><span class="loc">96</span><span class="prev">// 대량 변경이면 <mark>증분 갱신</mark> 대신 전체 재스캔</span></div>
        <div class="pgroup">Tests/WatcherTests.swift</div>
        <div class="pitem"><span class="loc">33</span><span class="prev">func test_<mark>증분_갱신</mark>_500ms_이내() async {</span></div>
      </div>`;
  if (state === 'regex-error') {
    return `    <aside class="panel" aria-label="전문 검색 패널">
${tabs}
      <div class="search-row"><input class="input err" value="([unclosed" aria-label="검색어" aria-invalid="true"><button class="toggle on" aria-pressed="true">.*</button></div>
      <div class="field-error"><span>⚠</span><span>잘못된 정규식: 닫히지 않은 그룹 '(' — 위치 1</span></div>
      <div class="result-meta">이전 결과 유지 (새 검색 미실행)</div>
${results(true)}
    </aside>`;
  }
  if (state === 'empty') {
    return `    <aside class="panel" aria-label="전문 검색 패널">
${tabs}
      <div class="search-row"><input class="input" value="zzzNotFound" aria-label="검색어"><button class="toggle" aria-pressed="false">.*</button></div>
      <div class="panel-empty">결과 없음</div>
    </aside>`;
  }
  return `    <aside class="panel" aria-label="전문 검색 패널">
${tabs}
      <div class="search-row"><input class="input" value="증분 갱신" aria-label="검색어"><button class="toggle" aria-pressed="false">.*</button></div>
      <div class="result-meta">500건 표시 · 4,812 파일 검색 · 0.8초</div>
      <div class="cap-bar">상위 500건만 표시합니다 — 검색어를 더 구체적으로 좁혀 주세요</div>
${results(false)}
    </aside>`;
}

// ── 상태바 ────────────────────────────────────────────────────────────
const IDX = {
  none: `<span class="chip" title="열린 프로젝트 없음"><i class="dot dot-none"></i>인덱스 없음</span>`,
  ready: `<span class="chip" title="마지막 갱신 09:41:12 · 4,812 파일 · 38,204 심볼"><i class="dot dot-ok"></i>인덱스 최신</span>`,
  indexing: `<span class="chip warn" title="직전 인덱스로 응답 중 — 결과가 잠시 이전 상태일 수 있습니다"><i class="spinner"></i>인덱싱 중 1,284/4,812<i class="mini-progress"><i style="width:27%"></i></i></span>`,
  updating: `<span class="chip warn" title="직전 인덱스로 응답 중"><i class="dot dot-warn"></i>갱신 중</span>`,
  rescan: `<span class="chip warn" title="대량 변경 감지 — 전체 재스캔으로 폴백"><i class="spinner warn"></i>전체 재스캔 중 2,140/4,812<i class="mini-progress warn"><i style="width:44%"></i></i></span>`,
};
const SES = {
  connecting: `<span class="chip warn"><i class="spinner warn"></i>편집 세션 연결 중</span>`,
  connected: `<span class="chip"><i class="dot dot-ok"></i>편집 세션 연결됨</span>`,
  lost: `<span class="chip err"><i class="dot dot-err"></i>편집 세션 끊김</span>`,
};
const MODE = {
  normal: `<span class="mode-chip mode-normal">NORMAL</span><span class="mode-layer">Vim</span>`,
  insert: `<span class="mode-chip mode-insert">INSERT</span><span class="mode-layer">Vim</span>`,
  visual: `<span class="mode-chip mode-visual">VISUAL</span><span class="mode-layer">Vim</span>`,
  command: `<span class="mode-chip mode-command">COMMAND</span><span class="mode-layer">Vim</span>`,
  standard: `<span class="mode-chip mode-standard">표준</span><span class="mode-layer">맥 기본 편집</span>`,
  off: `<span class="mode-chip mode-off">편집 불가</span><span class="mode-layer">세션 끊김</span>`,
};
const HINT = {
  vim: `:w 저장 · gd 정의 이동 · ⌃O 뒤로`,
  standard: `⌘S 저장 · ⌘B 정의 이동 · ⌘[ 뒤로`,
  none: '',
};

function statusbar({ mode = 'normal', hint = 'vim', path = 'Sources/Index/<b>SymbolIndex.swift</b>', dirty = false, msg = '', pos = '8:5', lang = 'Swift', index = 'ready', session = 'connected' } = {}) {
  const center = msg || (hint !== 'none' ? `<span class="sb-hint">${HINT[hint]}</span>` : '');
  return `  <footer class="statusbar" role="status">
    <div class="sb-left">
      ${MODE[mode]}
      <span class="sb-sep"></span>
      <span class="sb-path">${path}</span>${dirty ? dot : ''}
    </div>
    <div class="sb-center">${center}</div>
    <div class="sb-right">
      <span>${pos}</span><span class="sb-sep"></span><span>${lang}</span>
      ${IDX[index]}
      ${SES[session]}
    </div>
  </footer>`;
}

// ── 페이지 셸 ─────────────────────────────────────────────────────────
function page({ title, theme = 'dark', body, extraHead = '' }) {
  return `<!doctype html>
<html lang="ko" data-theme="${theme}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<link rel="stylesheet" href="styles.css">${extraHead}
</head>
<body>
${body}
</body>
</html>
`;
}

const win = (parts) => `<div class="app">\n${parts.join('\n')}\n</div>`;

// ── 페이지 정의 ───────────────────────────────────────────────────────
const pages = {};

// W-1 메인 창 정상 (Vim NORMAL · 참조 패널 · 인덱스 최신) — 다크
const mainNormalBody = win([
  titlebar({ file: 'SymbolIndex.swift' }),
  `  <div class="body">`,
  tree({}),
  editor({ hl: 8 }),
  panelRefs({}),
  `  </div>`,
  statusbar({}),
]);
pages['main-normal'] = page({ title: 'W-1 메인 창 — 정상(Vim NORMAL · 참조 패널)', theme: 'dark', body: mainNormalBody });
pages['main-light'] = page({ title: 'W-1 메인 창 — 라이트 테마(시스템 설정 추종)', theme: 'light', body: mainNormalBody });

// W-1b 표준 모드 + 더티 버퍼
pages['standard-mode'] = page({
  title: 'W-1 메인 창 — 표준 모드 + 더티 버퍼',
  theme: 'dark',
  body: win([
    titlebar({ file: 'SymbolIndex.swift', dirty: true, mode: 'standard' }),
    `  <div class="body">`,
    tree({ dirty: true }),
    editor({
      hl: 0, nvimMode: 'INSERT', dirty: true,
      dirtyLine: `    <span class="k">func</span> <span class="f">symbolCount</span>() -> <span class="t">Int</span> { byName.values.<span class="f">reduce</span>(<span class="n">0</span>) { $0 + $1.count }<span class="caret-block"> </span>}`,
    }),
    panelRefs({ state: 'initial' }),
    `  </div>`,
    statusbar({ mode: 'standard', hint: 'standard', dirty: true, pos: '20:58' }),
  ]),
});

// W-2 프로젝트 열기(빈 상태 + 최근 목록)
pages['open-project'] = page({
  title: 'W-2 프로젝트 열기 — 빈 상태 + 최근 프로젝트',
  theme: 'dark',
  body: win([
    titlebar({ project: 'code-navigator-mac', panelOn: false, noProject: true }),
    `  <div class="body no-panel" style="grid-template-columns: minmax(0,1fr)">
    <section class="welcome">
      <div class="welcome-card">
        <div class="app-mark">CN</div>
        <h1>프로젝트를 여세요</h1>
        <p class="desc">로컬 레포 폴더를 열면 트리가 표시되고 인덱싱이 시작됩니다.</p>
        <div style="display:flex;gap:8px;justify-content:center;margin-bottom:24px">
          <button class="btn-primary">프로젝트 열기…&nbsp; <span style="opacity:.75;font-weight:400">⌘O</span></button>
        </div>
        <div class="recent">
          <div class="recent-title">최근 프로젝트</div>
          <div class="recent-item"><span class="rname">code-navigator</span><span class="rpath">~/repo/code-navigator</span><span class="rtime">오늘 09:12</span></div>
          <div class="recent-item"><span class="rname">Get-Off-Early</span><span class="rpath">~/Documents/repo/Get-Off-Early</span><span class="rtime">어제</span></div>
          <div class="recent-item"><span class="rname">message-platform</span><span class="rpath">~/repo/message-platform</span><span class="rtime">8월 26일</span></div>
        </div>
        <p class="welcome-foot">인덱싱은 <code>.gitignore</code>와 기본 제외 목록(node_modules · build · dist · .git · target)을 존중합니다</p>
      </div>
    </section>
  </div>`,
    statusbar({ mode: 'normal', hint: 'none', path: '열린 프로젝트 없음', pos: '—', lang: '—', index: 'none', session: 'connected' }),
  ]),
});

// W-3 심볼 퍼지 검색 모달
pages['symbol-search'] = page({
  title: 'W-3 심볼 퍼지 검색 모달',
  theme: 'dark',
  body: win([
    titlebar({ file: 'SymbolIndex.swift' }),
    `  <div class="body">`,
    tree({}),
    editor({ hl: 8 }),
    panelRefs({ state: 'initial' }),
    `  </div>`,
    statusbar({}),
  ]) + `
<div class="overlay">
  <div class="modal" role="dialog" aria-modal="true" aria-label="심볼 검색">
    <div class="modal-input-wrap"><span class="ico">🔍</span><span class="modal-input">symidx</span></div>
    <div class="modal-note">인덱싱 중 — 결과가 아직 부분적일 수 있습니다 (1,284/4,812)</div>
    <div class="mlist" role="listbox">
      <div class="mitem sel" role="option" aria-selected="true"><span class="kind kind-C">C</span><span class="name"><mark>Sym</mark>bol<mark>Idx</mark>Store</span><span class="loc">Sources/Index/SymbolIdxStore.swift:14</span></div>
      <div class="mitem"><span class="kind kind-C">C</span><span class="name"><mark>Sym</mark>bol<mark>I</mark>n<mark>d</mark>e<mark>x</mark></span><span class="loc">Sources/Index/SymbolIndex.swift:4</span></div>
      <div class="mitem"><span class="kind kind-F">F</span><span class="name"><mark>sym</mark>bol<mark>Idx</mark>Of</span><span class="loc">Sources/Search/Fuzzy.swift:81</span></div>
      <div class="mitem"><span class="kind kind-P">P</span><span class="name"><mark>sym</mark>bol<mark>Idx</mark>Cache</span><span class="loc">Sources/App.swift:23</span></div>
      <div class="mitem"><span class="kind kind-T">T</span><span class="name"><mark>Sym</mark>bol<mark>Idx</mark>Key</span><span class="loc">Sources/Index/Symbol.swift:52</span></div>
      <div class="mitem"><span class="kind kind-I">I</span><span class="name"><mark>Sym</mark>bol<mark>Idx</mark>Reading</span><span class="loc">Sources/Index/Protocols.swift:9</span></div>
    </div>
    <div class="modal-foot"><span><kbd>↑↓</kbd> 이동</span><span><kbd>⏎</kbd> 정의로 이동</span><span><kbd>esc</kbd> 닫기</span></div>
  </div>
</div>`,
});

// W-4 정의 후보 목록(팝오버)
pages['definition-picker'] = page({
  title: 'W-4 정의 후보 목록 — 동명 3건',
  theme: 'dark',
  body: win([
    titlebar({ file: 'App.swift' }),
    `  <div class="body">`,
    tree({ active: 'App.swift' }),
    editor({
      hl: 0, file: 'App.swift',
      popover: `      <div class="popover" style="left:120px; top:150px" role="dialog" aria-label="정의 후보">
        <div class="pop-head"><b>parse</b> 정의 3건 — 이동할 위치를 선택하세요</div>
        <div class="pop-item sel"><span class="kind kind-F">F</span><span>parse(_ url: URL)</span><span class="loc">Index/Parser.swift:41</span></div>
        <div class="pop-item"><span class="kind kind-F">F</span><span>parse(_ text: String)</span><span class="loc">Index/SwiftParser.swift:37</span></div>
        <div class="pop-item"><span class="kind kind-F">F</span><span>parse(args:)</span><span class="loc">Util/ArgParse.swift:12</span></div>
        <div class="pop-foot"><a href="#">이 이름의 참조 보기 ⇧⌘B</a><span><kbd>↑↓</kbd> <kbd>⏎</kbd> <kbd>esc</kbd></span></div>
      </div>`,
    }),
    panelRefs({ state: 'initial' }),
    `  </div>`,
    statusbar({ path: 'Sources/<b>App.swift</b>', pos: '42:19' }),
  ]),
});

// W-6 전문 검색(정상 + 상한)
pages['fulltext-search'] = page({
  title: 'W-6 전문 검색 패널 — 결과 상한 도달',
  theme: 'dark',
  body: win([
    titlebar({ file: 'SymbolIndex.swift' }),
    `  <div class="body">`,
    tree({}),
    editor({ hl: 13 }),
    panelSearch({}),
    `  </div>`,
    statusbar({ pos: '13:9' }),
  ]),
});

// W-8 편집 세션 끊김
pages['edit-session-lost'] = page({
  title: 'W-8 편집 세션 끊김 — 편집 비활성 + 재기동 안내',
  theme: 'dark',
  body: win([
    titlebar({ file: 'SymbolIndex.swift', dirty: true }),
    `  <div class="body">`,
    tree({ dirty: true }),
    editor({
      hl: 0, dirty: true, disabled: true,
      overlay: `      <div class="editor-overlay" role="alertdialog" aria-label="편집 세션 끊김">
        <div class="state-card">
          <span class="glyph">⚠️</span>
          <h2>편집 세션이 끊겼습니다</h2>
          <p>Neovim 프로세스가 종료되어 키 입력이 전달되지 않습니다.<br>편집을 계속하려면 편집 세션을 재기동하세요.</p>
          <p class="hint">재기동하면 파일은 디스크 내용으로 다시 열립니다. 마지막 저장 이후의 변경은 남아 있지 않을 수 있습니다.<br>트리·심볼 검색·참조·전문 검색은 계속 사용할 수 있습니다.</p>
          <div class="actions"><button class="btn-primary">편집 세션 재기동 ⌃⌘R</button></div>
        </div>
      </div>`,
    }),
    panelRefs({}),
    `  </div>`,
    statusbar({ mode: 'off', hint: 'none', dirty: true, msg: `<span class="sb-msg err">⚠ 편집 세션이 끊겼습니다 — ⌃⌘R로 재기동</span>`, pos: '—', session: 'lost' }),
  ]),
});

Object.assign(pages, makeExtraPages({ page, win, titlebar, tree, editor, panelRefs, panelSearch, statusbar, IDX, SES, MODE, HINT, dot }));

writeFileSync(join(ROOT, '_pages.json'), JSON.stringify(Object.keys(pages), null, 2));
for (const [name, html] of Object.entries(pages)) {
  writeFileSync(join(ROOT, `${name}.html`), html);
  console.log(`✓ ${name}.html`);
}
export { titlebar, tree, editor, panelRefs, panelSearch, statusbar, page, win, IDX, SES, MODE, HINT, dot };
