// PD 자가 검증용 스크린샷 도구 — CDP(Emulation.setDeviceMetricsOverride)로 창 크기를 정확히 재현한다.
// 이 앱은 데스크톱 전용이므로 모바일 뷰포트는 촬영하지 않는다. 대신 창 크기 2종 + 좁은 창 1종(레이아웃 적응 규칙 검증).
// 사용: node shoot.mjs [페이지명...]  (생략 시 전체)
import { spawn } from 'node:child_process';
import { writeFileSync, mkdtempSync, rmSync, mkdirSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const ROOT = dirname(fileURLToPath(import.meta.url));
const ALL_PAGES = JSON.parse(readFileSync(join(ROOT, '_pages-2b.json'), 'utf8'));
const pages = process.argv.length > 2 ? process.argv.slice(2) : ALL_PAGES;

// 작은 창 = 노트북에서 흔한 크기, 큰 창 = 외장 모니터 전체 폭
const SMALL = { name: 'small', width: 1000, height: 700, deviceScaleFactor: 2 };
const LARGE = { name: 'large', width: 1600, height: 1000, deviceScaleFactor: 2 };
// 좁은 창 = 패널 오버레이 전환 경계(<900px) 검증용 — 대표 화면만
const NARROW = { name: 'narrow', width: 820, height: 620, deviceScaleFactor: 2 };
const EXTRA = { 'tabs-main': [NARROW], 'render-markdown': [NARROW] };

mkdirSync(join(ROOT, 'shots'), { recursive: true });
const profile = mkdtempSync(join(tmpdir(), 'cnmac-proto-'));
const PORT = 9226;
const chrome = spawn(CHROME, [
  '--headless=new', '--disable-gpu', '--hide-scrollbars',
  `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`, 'about:blank',
], { stdio: 'ignore' });

const wait = (ms) => new Promise((r) => setTimeout(r, ms));
try {
  let targets = null;
  for (let i = 0; i < 50 && !targets; i++) {
    try { targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json(); } catch { await wait(200); }
  }
  if (!targets) throw new Error('Chrome DevTools 포트에 연결하지 못했습니다');
  const target = targets.find((t) => t.type === 'page');
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

  let seq = 0;
  const pending = new Map();
  ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  };
  const send = (method, params = {}) => new Promise((res) => {
    const id = ++seq; pending.set(id, res);
    ws.send(JSON.stringify({ id, method, params }));
  });

  for (const name of pages) {
    await send('Page.navigate', { url: `file://${ROOT}/${name}.html` });
    await wait(450);
    for (const vp of [SMALL, LARGE, ...(EXTRA[name] || [])]) {
      await send('Emulation.setDeviceMetricsOverride', {
        width: vp.width, height: vp.height, deviceScaleFactor: vp.deviceScaleFactor, mobile: false,
      });
      await wait(250);
      const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true });
      const out = join(ROOT, 'shots', `${name}-${vp.name}.png`);
      writeFileSync(out, Buffer.from(shot.result.data, 'base64'));
      console.log(`✓ ${name}-${vp.name}.png (${vp.width}x${vp.height}@${vp.deviceScaleFactor}x)`);
    }
  }
  ws.close();
} finally {
  chrome.kill();
  await wait(500);
  try { rmSync(profile, { recursive: true, force: true }); } catch { /* 임시 디렉토리 — OS가 정리 */ }
}
