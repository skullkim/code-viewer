// 2차 디자인(02b_design.md) 프로토타입 생성기 — W-11~W-15.
// 1차 build.mjs 의 공통 셸(트리·에디터·패널)을 그대로 재사용하고, 바뀐 부분(툴바에서 프로젝트 팝업 제거,
// 탭 바 추가, 렌더 표면, 읽기 전용 모드 칩)만 여기서 다시 만든다. 1차 파일은 한 줄도 고치지 않는다.
// 사용: node build-2b.mjs   → node shoot-2b.mjs
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tree, editor, panelRefs, IDX, SES, dot } from './build.mjs';

const ROOT = dirname(fileURLToPath(import.meta.url));
const EXTRA_CSS = '\n<link rel="stylesheet" href="styles-2b.css">';

function page({ title, theme = 'dark', body }) {
  return `<!doctype html>
<html lang="ko" data-theme="${theme}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<link rel="stylesheet" href="styles.css">${EXTRA_CSS}
</head>
<body>
${body}
</body>
</html>
`;
}

// ── 툴바 (C-1: 프로젝트 팝업 제거 — 전환은 탭이, 추가는 ＋/⌘O 가 맡는다) ──────────
function titlebar2({ file = 'SymbolIndex.swift', dirty = false, mode = 'vim', render = 'none' } = {}) {
  const renderBtn = render === 'none' ? ''
    : `<button class="tb-btn${render === 'on' ? ' on' : ''}" aria-pressed="${render === 'on'}"${render === 'off' ? '' : ''}><span class="ico">▣</span><span class="lbl">렌더</span><kbd>⇧⌘V</kbd></button>`;
  return `  <header class="titlebar">
    <div class="lights"><span class="light l-close"></span><span class="light l-min"></span><span class="light l-max"></span></div>
    <div class="win-title">${file}${dirty ? ' ' + dot : ''}</div>
    <div class="tb-spacer"></div>
    <div class="tb-group">
      <div class="seg" role="group" aria-label="입력 모드">
        <button class="${mode === 'vim' ? 'on' : ''}" aria-pressed="${mode === 'vim'}">Vim</button>
        <button class="${mode === 'standard' ? 'on' : ''}" aria-pressed="${mode === 'standard'}">표준</button>
      </div>
      <button class="tb-btn"><span class="ico">🔍</span><span class="lbl">심볼</span><kbd>⌘P</kbd></button>
      <button class="tb-btn"><span class="ico">☰</span><span class="lbl">전문 검색</span><kbd>⇧⌘F</kbd></button>
      ${renderBtn}
      <button class="tb-btn" aria-pressed="true"><span class="lbl">패널</span><kbd>⌥⌘0</kbd></button>
    </div>
  </header>`;
}

// ── W-11 탭 바 ─────────────────────────────────────────────────────────
// t = { name, dis?, active?, indexing?, dirty?, showClose? }
function ptab(t) {
  const cls = ['ptab', t.active ? 'active' : '', t.showClose ? 'show-close' : '', t.dragging ? 'dragging' : ''].filter(Boolean).join(' ');
  const spin = t.indexing ? `<i class="tab-spin" aria-hidden="true"></i>` : '';
  const dis = t.dis ? ` <span class="pdis">· ${t.dis}</span>` : '';
  const tip = t.tip || `${t.name}\n${t.path || ''}`;
  const slot = `<span class="tslot">${t.dirty ? `<i class="tdot" title="저장하지 않은 변경 ${t.dirtyCount || 2}건"></i>` : ''}<button class="tclose" aria-label="'${t.name}' 탭 닫기">✕</button></span>`;
  return `        <div class="${cls}" role="tab" aria-selected="${!!t.active}" title="${tip}">${spin}<span class="plabel">${t.name}${dis}</span>${slot}</div>`;
}
function tabbar(tabs, { overflow = 0, menu = false, drop = -1, tail = true } = {}) {
  const strip = tabs.map((t, i) => (i === drop ? `        <div class="tab-drop"></div>\n` : '') + ptab(t)).join('\n');
  const ovf = overflow > 0
    ? `<button class="tab-btn wide" aria-haspopup="menu" aria-label="열린 프로젝트 모두 보기">≫<span class="ovf-n">${overflow}</span></button>`
    : '';
  const menuHtml = menu ? `
      <div class="ovf-menu" role="menu">
        <div class="ovf-title">열린 프로젝트</div>
        <div class="ovf-item" role="menuitemradio" aria-checked="true"><span class="chk">✓</span><span class="nm">code-navigator-mac</span></div>
        <div class="ovf-item"><span class="chk"></span><span class="nm">Get-Off-Early</span><i class="tdot" style="width:7px;height:7px;border-radius:50%;background:var(--warning-solid)"></i></div>
        <div class="ovf-item"><span class="chk"></span><span class="nm"><i class="tab-spin" style="display:inline-block;vertical-align:-1px;margin-right:6px"></i>message-platform</span></div>
        <div class="ovf-item"><span class="chk"></span><span class="nm">knowledge-web</span></div>
        <div class="ovf-item"><span class="chk"></span><span class="nm">app · frontend</span></div>
        <div class="ovf-item"><span class="chk"></span><span class="nm">app · backend</span></div>
      </div>` : '';
  return `  <div class="tabbar" role="tablist" aria-label="프로젝트 탭">
      <div class="tabstrip">
${strip}
      </div>
      ${tail === false ? '' : `<div class="tabbar-tail">
        ${ovf}
        <button class="tab-btn" aria-label="프로젝트 열기 (⌘O)" title="프로젝트 열기 (⌘O)">＋</button>
      </div>`}${menuHtml}
  </div>`;
}

// ── 상태바 (C-6: 렌더 보기 = 7번째 모드 상태) ────────────────────────────
const MODE2 = {
  normal: `<span class="mode-chip mode-normal">NORMAL</span><span class="mode-layer">Vim</span>`,
  read: `<span class="mode-chip mode-read">읽기 전용</span><span class="mode-layer">렌더 보기</span>`,
};
function statusbar2({ mode = 'normal', path, dirty = false, center = '', pos = '8:5', lang = 'Swift', index = 'ready', session = 'connected' }) {
  return `  <footer class="statusbar" role="status">
    <div class="sb-left">
      ${MODE2[mode]}
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

// ── W-14/W-15 렌더 표면 ────────────────────────────────────────────────
function renderHead({ name = 'README.md', blocked = 0, spinner = false }) {
  const chip = blocked > 0
    ? `<button class="sandbox-chip has-blocked" aria-haspopup="dialog" title="원격 리소스와 스크립트를 차단하고 프로젝트 폴더 안의 파일만 표시합니다">🛡 차단됨 ${blocked}</button>`
    : `<button class="sandbox-chip" aria-haspopup="dialog" title="원격 리소스와 스크립트를 차단하고 프로젝트 폴더 안의 파일만 표시합니다">🛡 샌드박스</button>`;
  return `        <div class="render-head">
          <span class="rname">${name}</span>
          <span class="ro-badge">읽기 전용</span>
          ${chip}
          ${spinner ? `<span class="render-spin"><i class="spinner"></i></span>` : ''}
          <span class="spacer"></span>
          <button class="src-btn">&lt;/&gt; <span class="lbl">소스 보기</span> <kbd>⇧⌘V</kbd></button>
        </div>`;
}
const BLOCKED_IMG = `<div class="blocked-box" role="img" aria-label="차단된 원격 이미지: 빌드 상태 배지">
            <span class="bt">🛡 원격 이미지가 차단되었습니다</span>
            <span class="bhost">raw.githubusercontent.com</span>
            <span class="balt">alt: 빌드 상태 배지</span>
          </div>`;
const BLOCKED_OUTSIDE = `<div class="blocked-box" role="img" aria-label="차단된 파일: 프로젝트 폴더 밖">
            <span class="bt">🛡 프로젝트 폴더 밖의 파일은 표시하지 않습니다</span>
            <span class="bhost">../../design/diagram.png</span>
          </div>`;
const DOC_BODY = `          <div class="doc" role="document">
            <h1>code-navigator-mac</h1>
            <p>맥 네이티브 코드 내비게이터. <b>Neovim</b>을 임베드해 편집하고, 심볼 인덱스로 정의·참조를 즉시 찾는다.</p>
            ${BLOCKED_IMG}
            <h2>설치</h2>
            <pre><code>brew install neovim
swift build -c release</code></pre>
            <p>필요 버전은 <code>nvim 0.9.0</code> 이상이다. 자세한 내용은 <a href="#설계-원칙">설계 원칙</a>과 <a href="./docs/adr/0106-project-workspace.md">ADR 0106</a>을 보라.</p>
            <h2 id="설계-원칙">설계 원칙</h2>
            <ul>
              <li>인덱스는 <b>파생물</b>이다 — 소스에서 전량 재생성할 수 있다.</li>
              <li>편집은 <b>Neovim 을 통해서만</b> 일어난다.</li>
              <li>사용자의 <code>~/.config/nvim</code> 설정을 침범하지 않는다.</li>
            </ul>
            <blockquote>조회 결과가 소스와 일치할 때만 인덱스를 “최신”이라 부른다.</blockquote>
            <h3>측정된 값</h3>
            <table>
              <tr><th>항목</th><th>값</th></tr>
              <tr><td>앱 기준선</td><td>95 MB</td></tr>
              <tr><td>인덱스 비용</td><td>19 MB / 25,000 심볼</td></tr>
            </table>
            <span class="doc-img"></span>
            <span class="doc-cap">↑ 프로젝트 루트 안의 로컬 이미지는 그대로 표시된다 (docs/architecture.png)</span>
            ${BLOCKED_OUTSIDE}
          </div>`;

function renderSurface({ name = 'README.md', blocked = 2, body = DOC_BODY, spinner = false }) {
  return `      <div class="render-surface">
${renderHead({ name, blocked, spinner })}
        <div class="render-body">
${body}
        </div>
      </div>`;
}

const stateCard = (glyph, h2, p, actions) => `        <div class="render-state">
          <div class="state-card">
            <span class="glyph">${glyph}</span>
            <h2>${h2}</h2>
            <p>${p}</p>
            <div class="actions">${actions}</div>
          </div>
        </div>`;

const pages = {};
const win = (parts) => `<div class="app has-tabs">\n${parts.join('\n')}\n</div>`;

// ── 1. tabs-main — W-11 창 골격 안의 탭 바 ─────────────────────────────
const TABS3 = [
  { name: 'code-navigator-mac', active: true, path: '~/Documents/repo/code-navigator-mac' },
  { name: 'message-platform', indexing: true, tip: 'message-platform\n~/repo/message-platform\n인덱싱 중 1,284/4,812' },
  { name: 'Get-Off-Early', dirty: true, tip: 'Get-Off-Early\n~/Documents/repo/Get-Off-Early\n저장하지 않은 변경 2건' },
];
pages['tabs-main'] = page({
  title: 'W-11 프로젝트 탭 바 — 활성 · 인덱싱 중 · 더티',
  theme: 'dark',
  body: win([
    titlebar2({ file: 'SymbolIndex.swift' }),
    tabbar(TABS3),
    `  <div class="body">`,
    tree({}),
    editor({ hl: 8 }),
    panelRefs({}),
    `  </div>`,
    statusbar2({ path: 'Sources/Index/<b>SymbolIndex.swift</b>', center: `<span class="sb-hint">:w 저장 · gd 정의 이동 · ⌃O 뒤로</span>` }),
  ]),
});

// ── 2. render-markdown — W-14 렌더 보기 정상 ───────────────────────────
pages['render-markdown'] = page({
  title: 'W-14 렌더 보기 — 마크다운 정상 + 차단 2건',
  theme: 'dark',
  body: win([
    titlebar2({ file: 'README.md', render: 'on' }),
    tabbar([
      { name: 'code-navigator-mac', active: true, path: '~/Documents/repo/code-navigator-mac' },
      { name: 'Get-Off-Early', path: '~/Documents/repo/Get-Off-Early' },
    ]),
    `  <div class="body">`,
    tree({ active: 'README.md' }),
    editor({ hl: 8, overlay: renderSurface({}) }),
    panelRefs({ state: 'initial' }),
    `  </div>`,
    statusbar2({
      mode: 'read', path: '<b>README.md</b>', pos: '—', lang: 'Markdown',
      center: `<span class="sb-hint">⇧⌘V 소스 보기</span>`,
    }),
  ]),
});

// ── 3. tabs-states — W-11/12/13 상태 갤러리 ────────────────────────────
const galTabs = (tabs, opts) => `<div class="gal-frame">${tabbar(tabs, opts)}</div>`;
const galTabsBare = (tabs, opts = {}) => galTabs(tabs, { ...opts, tail: false });
pages['tabs-states'] = page({
  title: 'W-11~13 상태 갤러리 — 탭 · 넘침 · 복원 실패 · 닫기 확인',
  theme: 'dark',
  body: `<div class="gallery">
  <h1>02b §3 — 프로젝트 탭 상태 갤러리 (W-11 · W-12 · W-13)</h1>
  <p class="lead">프론트는 이 렌더를 구현 타깃으로, QA는 실제 앱을 이것과 대조한다. 새 색 토큰 0개 — 기존 표면·텍스트 토큰만 쓴다.</p>

  <h2>1. 탭 하나의 상태 6종</h2>
  <div class="grid">
    <div class="spec"><div class="cap"><b>활성 · 클린</b> — bg-content 채움 + text-1 600 + 상단 2px accent</div>${galTabsBare([{ name: 'code-navigator-mac', active: true }])}</div>
    <div class="spec"><div class="cap"><b>비활성 · 클린</b> — 투명 + text-2 500 (대비 6.25:1 / 5.43:1)</div>${galTabsBare([{ name: 'Get-Off-Early' }])}</div>
    <div class="spec"><div class="cap"><b>비활성 · 인덱싱 중</b> — 9px 스피너, 숫자는 툴팁으로만</div>${galTabsBare([{ name: 'message-platform', indexing: true }])}</div>
    <div class="spec"><div class="cap"><b>비활성 · 더티</b> — ● warning-solid (hover 시 ✕ 로 교체)</div>${galTabsBare([{ name: 'knowledge-web', dirty: true }])}</div>
    <div class="spec"><div class="cap"><b>hover</b> — 닫기 ✕ 노출 (키보드 경로는 ⌘W)</div>${galTabsBare([{ name: 'Get-Off-Early', showClose: true }])}</div>
    <div class="spec"><div class="cap"><b>동명 구분</b> — 폴더 이름이 겹칠 때만 상위 1단계</div>${galTabsBare([{ name: 'app', dis: 'frontend' }, { name: 'app', dis: 'backend' }])}</div>
  </div>

  <h2>2. 탭 개수별 — 1개 / 여러 개 / 넘침</h2>
  <div class="grid">
    <div class="spec wide"><div class="cap"><b>탭 1개</b> — 탭 바를 표시한다(AC-1 문면). ＋ 가 “여러 개 열 수 있음”을 상시 알린다 · 판정 요청 §10-1</div>${galTabs([{ name: 'code-navigator-mac', active: true }])}</div>
    <div class="spec wide"><div class="cap"><b>탭 3개</b> — 남는 폭을 균등 분배하되 <b>220px 상한</b>. 넓은 창에서 남는 자리는 창 드래그 영역</div>${galTabs(TABS3)}</div>
    <div class="spec wide"><div class="cap"><b>넘침</b> — 가로 스크롤 + <code>≫3</code>. 활성 탭은 항상 스크롤되어 보인다</div>${galTabs([
      { name: 'code-navigator-mac', active: true },
      { name: 'Get-Off-Early', dirty: true },
      { name: 'message-plat…', indexing: true },
      { name: 'knowledge-web' },
      { name: 'app', dis: 'frontend' },
      { name: 'app', dis: 'backend' },
    ], { overflow: 3 })}</div>
    <div class="spec wide"><div class="cap"><b>넘침 메뉴</b> — 가로 스크롤 제스처 없이 모든 탭에 도달(접근성). 활성 ✓ · 더티 ● · 인덱싱 스피너를 그대로 옮긴다</div>
      <div class="gal-frame" style="height:300px;position:relative">${tabbar([
        { name: 'code-navigator-mac', active: true },
        { name: 'Get-Off-Early', dirty: true },
        { name: 'message-plat…', indexing: true },
      ], { overflow: 3, menu: true })}</div>
    </div>
    <div class="spec wide"><div class="cap"><b>드래그 재정렬</b> — 잡힌 탭이 떠오르고 드롭 위치에 2px accent 삽입 표시. 순서는 즉시 저장되어 재시작에 복원(AC-4)</div>${galTabs([
      { name: 'code-navigator-mac', active: true },
      { name: 'knowledge-web', dragging: true },
      { name: 'Get-Off-Early' },
    ], { drop: 2 })}</div>
    <div class="spec wide"><div class="cap"><b>탭 0개</b> — 탭 바 자체가 없다. 웰컴 화면(W-2)으로 돌아간다</div>
      <div class="gal-frame" style="padding:16px;text-align:center;color:var(--text-2);font-size:12.5px">탭 바 없음 — W-2 웰컴 화면 (기존 <code>open-project.html</code>)</div>
    </div>
  </div>

  <h2>3. 라이트 / 다크 병치 (새 색 토큰 0개)</h2>
  <div class="theme-pair">
    <div class="theme-box" data-theme="light"><div class="cap" style="font-size:11px;color:var(--text-3);margin-bottom:8px">라이트</div>${galTabs(TABS3)}</div>
    <div class="theme-box" data-theme="dark"><div class="cap" style="font-size:11px;color:var(--text-3);margin-bottom:8px">다크</div>${galTabs(TABS3)}</div>
  </div>

  <h2>4. W-12 복원 실패 시트 — 사유를 마스킹하지 않고, 여러 건을 한 장에 묶는다</h2>
  <div class="sheet-demo" style="height:310px">
    <div class="sheet" style="width:min(460px,100%)">
      <div style="text-align:center"><span class="glyph">⚠️</span></div>
      <h2>일부 프로젝트를 복원하지 못했습니다</h2>
      <p>다음 2개 프로젝트는 열 수 없어 탭 목록에서 제거했습니다.</p>
      <ul>
        <li>message-platform<br><span class="why">경로를 찾을 수 없습니다: ~/repo/message-platform</span></li>
        <li>old-prototype<br><span class="why">폴더에 접근할 권한이 없습니다: /Volumes/ext/old-prototype</span></li>
      </ul>
      <div class="actions"><button class="btn-primary">확인</button></div>
    </div>
  </div>

  <h2>5. W-13 탭 닫기 확인 시트 — 더티 버퍼가 있을 때만</h2>
  <div class="sheet-demo" style="height:300px">
    <div class="sheet" style="width:min(460px,100%)">
      <div style="text-align:center"><span class="glyph">●</span></div>
      <h2>'Get-Off-Early' 탭에 저장하지 않은 변경이 있습니다</h2>
      <p>저장하지 않고 닫으면 다음 파일의 변경 사항이 사라집니다.</p>
      <ul>
        <li><span class="why">knowledge/index-core.mjs</span></li>
        <li><span class="why">README.md</span></li>
      </ul>
      <div class="actions">
        <button class="btn-ghost">취소</button>
        <button class="btn-ghost">저장하지 않고 닫기</button>
        <button class="btn-primary">저장 후 닫기</button>
      </div>
    </div>
  </div>

  <h2>6. 단축키 — 전부 ⌘ 조합(키 라우팅 계약 준수). ⌃Tab 은 Neovim 것이라 쓰지 않는다</h2>
  <div class="menu-cards" style="padding:0">
    <div class="menu-card">
      <div class="mc-title">탭</div>
      <div class="menu-row">다음 탭<span class="sc">⇧⌘]</span></div>
      <div class="menu-row">이전 탭<span class="sc">⇧⌘[</span></div>
      <div class="menu-row">N번째 탭<span class="sc">⌘1…⌘8</span></div>
      <div class="menu-row">마지막 탭<span class="sc">⌘9</span></div>
      <div class="menu-div"></div>
      <div class="menu-row">탭 닫기<span class="sc">⌘W</span></div>
      <div class="menu-row">창 닫기<span class="sc">⇧⌘W</span></div>
      <div class="menu-row">프로젝트 열기…<span class="sc">⌘O</span></div>
    </div>
    <div class="menu-card">
      <div class="mc-title">보기</div>
      <div class="menu-row"><span class="check">✓</span>렌더 보기<span class="sc">⇧⌘V</span></div>
      <div class="menu-row"><span class="check"></span>파일 트리 표시<span class="sc">⌥⌘1</span></div>
      <div class="menu-row"><span class="check">✓</span>참조·검색 패널 표시<span class="sc">⌥⌘0</span></div>
    </div>
    <div class="menu-card">
      <div class="mc-title">렌더 보기에서 비활성</div>
      <div class="menu-row disabled">정의로 이동<span class="sc">⌘B</span></div>
      <div class="menu-row disabled">참조 보기<span class="sc">⇧⌘B</span></div>
      <div class="menu-div"></div>
      <div class="menu-row">심볼 검색…<span class="sc">⌘P</span></div>
      <div class="menu-row">전문 검색…<span class="sc">⇧⌘F</span></div>
    </div>
  </div>
  <div class="chrome-note">
    <h2>왜 이 배치인가</h2>
    <ul>
      <li><b>탭 바는 툴바 아래.</b> 탭 아래의 모든 것(트리·에디터·패널·상태바)이 그 탭 소유이고, 위의 툴바는 창 전역 동작이다. 트래픽 라이트와도 겹치지 않는다.</li>
      <li><b>진행률 숫자는 탭에 넣지 않는다.</b> 탭 안에서는 10px대가 되는데, 이 빌드에서 비-Retina 디스플레이의 11px대 조밀 글리프가 뭉개진다는 실측이 나왔다. 숫자는 툴팁·상태바 칩·인덱스 팝오버가 소유한다.</li>
      <li><b>더티 ● 는 뺄 수 없다.</b> 배경 탭의 저장 안 된 변경은 다른 어떤 표면에도 보이지 않는다(상태바는 활성 탭 것).</li>
    </ul>
  </div>
</div>`,
});

// ── 4. render-states — W-14/W-15 상태 갤러리 ───────────────────────────
const docFrame = (inner) => `<div class="doc-frame">${inner}</div>`;
pages['render-states'] = page({
  title: 'W-14~15 상태 갤러리 — 렌더 중 · 빈 · 실패 3종 · 차단 고지',
  theme: 'dark',
  body: `<div class="gallery">
  <h1>02b §3 — 문서 렌더 상태 갤러리 (W-14 · W-15)</h1>
  <p class="lead">렌더 보기는 Neovim 그리드 <b>위에 얹는 별도 표면</b>이다. 그리드는 크기가 바뀌지 않고 가려질 뿐이다.</p>

  <h2>1. 어느 쪽을 보고 있는지 드러내는 3중 표시 (AC-3)</h2>
  <div class="grid">
    <div class="spec wide"><div class="cap"><b>① 툴바 토글</b> · <b>② 렌더 헤더 바</b> · <b>③ 상태바 모드 칩</b></div>
      ${docFrame(renderHead({ name: 'README.md', blocked: 2 }))}
      <div style="height:8px"></div>
      <div class="sb-demo"><span class="mode-chip mode-read">읽기 전용</span><span class="mode-layer">렌더 보기</span><span class="sb-sep"></span><span class="sb-path"><b>README.md</b></span><span style="flex:1"></span><span>Markdown</span>${IDX.ready}${SES.connected}</div>
      <div style="margin-top:8px;font-size:11.5px;color:var(--text-2)">렌더 보기 동안 키 입력은 Neovim 에 전달되지 않는다 — 모드 칩이 <code>NORMAL</code> 을 계속 보여주면 거짓말이 된다.</div>
    </div>
    <div class="spec"><div class="cap"><b>차단 0건</b> — 그래도 샌드박스 칩은 상시 표시</div>${docFrame(renderHead({ name: 'CHANGELOG.md', blocked: 0 }))}</div>
    <div class="spec wide"><div class="cap"><b>재렌더(저장 후)</b> — 이전 렌더를 두고 헤더에만 스피너. 스크롤 위치 유지(AC-5)</div>${docFrame(renderHead({ name: 'README.md', blocked: 2, spinner: true }))}</div>
  </div>

  <h2>2. 빈 / 실패 상태 — 빈 화면을 보여주지 않는다 (AC-6)</h2>
  <div class="grid">
    <div class="spec"><div class="cap"><b>렌더 중(최초)</b> — 200ms 넘을 때만. 그 전엔 아무것도 그리지 않는다</div>
      ${docFrame(`<div class="render-state"><div class="render-spin"><i class="spinner"></i>문서를 렌더하는 중…</div></div>`)}</div>
    <div class="spec"><div class="cap"><b>빈 파일</b></div>
      ${docFrame(stateCard('📄', '빈 문서입니다', '이 파일에는 내용이 없습니다.', '<button class="btn-ghost">소스 보기 ⇧⌘V</button>'))}</div>
    <div class="spec"><div class="cap"><b>읽기 실패</b> — 사유를 마스킹하지 않는다</div>
      ${docFrame(stateCard('⚠️', '문서를 읽을 수 없습니다', '폴더에 접근할 권한이 없습니다: <code>/Volumes/ro/DOC.md</code>', '<button class="btn-ghost">소스 보기</button><button class="btn-primary">다시 시도</button>'))}</div>
    <div class="spec"><div class="cap"><b>인코딩 해석 불가</b></div>
      ${docFrame(stateCard('⚠️', '이 파일의 문자 인코딩을 해석할 수 없습니다', 'UTF-8 텍스트가 아닙니다. 소스 보기에서 열어 주세요.', '<button class="btn-ghost">소스 보기 ⇧⌘V</button>'))}</div>
    <div class="spec"><div class="cap"><b>크기 상한 초과</b> — 숫자는 천 단위 구분자 규칙을 따른다</div>
      ${docFrame(stateCard('⚠️', '문서가 너무 큽니다', '렌더 상한은 2MB입니다 (이 파일 5.4MB).', '<button class="btn-ghost">소스 보기 ⇧⌘V</button>'))}</div>
    <div class="spec wide"><div class="cap"><b>렌더 불가 파일에서 ⇧⌘V</b> — 툴바 버튼은 애초에 비활성</div>
      <div class="sb-demo"><span class="mode-chip mode-normal">NORMAL</span><span class="mode-layer">Vim</span><span class="sb-sep"></span><span style="color:var(--danger)">✕ 이 파일은 렌더할 수 없습니다 (.md · .html 만 지원)</span></div></div>
  </div>

  <h2>3. W-15 차단 고지 — 조용히 비우지 않는다 (INV-6)</h2>
  <div class="grid">
    <div class="spec"><div class="cap"><b>원격 이미지</b> — 자리를 비우지 않고 호스트·alt 를 보여준다</div><div style="padding:8px;background:var(--bg-content);border-radius:var(--radius-s)">${BLOCKED_IMG}</div></div>
    <div class="spec"><div class="cap"><b>프로젝트 밖 파일</b> — 루트는 <b>그 탭의 루트</b>다(INV-5)</div><div style="padding:8px;background:var(--bg-content);border-radius:var(--radius-s)">${BLOCKED_OUTSIDE}</div></div>
    <div class="spec"><div class="cap"><b>차단 팝오버</b> — 칩 클릭. 해제 버튼은 없다</div>
      <div class="blocked-pop">
        <div class="bp-head">이 문서에서 차단된 항목</div>
        <div class="bp-row"><span>원격 이미지</span><span class="n">2</span><span class="src">raw.githubusercontent.com</span></div>
        <div class="bp-row"><span>스크립트</span><span class="n">1</span><span class="src">(인라인)</span></div>
        <div class="bp-row"><span>원격 스타일시트</span><span class="n">1</span><span class="src">cdn.jsdelivr.net</span></div>
        <div class="bp-row"><span>프로젝트 밖 파일</span><span class="n">1</span><span class="src">../../.ssh/config</span></div>
        <div class="bp-foot">렌더 보기는 네트워크 요청을 하지 않고 스크립트를 실행하지 않습니다. 이 차단은 해제할 수 없습니다 — 원본 그대로 보려면 브라우저에서 파일을 여세요.</div>
      </div>
    </div>
    <div class="spec"><div class="cap"><b>차단 0건 팝오버</b></div>
      <div class="blocked-pop">
        <div class="bp-head">이 문서에서 차단된 항목</div>
        <div class="bp-row"><span style="color:var(--text-2)">차단된 항목이 없습니다</span></div>
        <div class="bp-foot">렌더 보기는 네트워크 요청을 하지 않고 스크립트를 실행하지 않습니다.</div>
      </div>
    </div>
    <div class="spec wide"><div class="cap"><b>HTML 문서 · 스크립트로 내용을 그리는 페이지</b> — 비어 보이는 이유를 본문 상단에서 말한다</div>
      ${docFrame(`<div class="doc" role="document">
        <div class="script-banner"><span>🛡</span><span>이 페이지는 스크립트로 내용을 그립니다 — 렌더 보기에서는 스크립트가 실행되지 않습니다.</span></div>
        <h1>Coverage Report</h1>
        <p>정적으로 담긴 부분만 표시됩니다.</p>
        <table><tr><th>모듈</th><th>커버리지</th></tr><tr><td>CodeNavigatorCore</td><td>94%</td></tr></table>
      </div>`)}
    </div>
  </div>

  <h2>4. 라이트 테마 병치 — 새 색 토큰 0개</h2>
  <div class="theme-pair">
    <div class="theme-box" data-theme="light">${docFrame(renderHead({ name: 'README.md', blocked: 2 }) + `<div class="doc"><h1>code-navigator-mac</h1><p>맥 네이티브 코드 내비게이터.</p>${BLOCKED_IMG}<pre><code>brew install neovim</code></pre></div>`)}</div>
    <div class="theme-box" data-theme="dark">${docFrame(renderHead({ name: 'README.md', blocked: 2 }) + `<div class="doc"><h1>code-navigator-mac</h1><p>맥 네이티브 코드 내비게이터.</p>${BLOCKED_IMG}<pre><code>brew install neovim</code></pre></div>`)}</div>
  </div>
</div>`,
});

writeFileSync(join(ROOT, '_pages-2b.json'), JSON.stringify(Object.keys(pages), null, 2));
for (const [name, html] of Object.entries(pages)) {
  writeFileSync(join(ROOT, `${name}.html`), html);
  console.log(`✓ ${name}.html`);
}
