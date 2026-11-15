import { VERTEX, WALLPAPERS, fragmentSource, SPEED, BRIGHTNESS, TINT, FPS } from './shaders.js';

const canvas = document.getElementById('wall');
const ui = document.getElementById('ui');
const picker = document.getElementById('picker');
const nameEl = document.getElementById('name');
const blurbEl = document.getElementById('blurb');
const playBtn = document.getElementById('play');
const fsBtn = document.getElementById('fullscreen');
const noteEl = document.getElementById('note');

const params = new URLSearchParams(location.search);
// ?t=123 draws one frame at that exact time (handy for comparing with the
// app's `--snapshot` output). ?ui=0 hides the controls, e.g. inside an iframe.
const fixedTime = params.has('t') ? parseFloat(params.get('t')) : null;
if (params.get('ui') === '0') document.body.classList.add('bare');

const gl = canvas.getContext('webgl2', {
  antialias: false, alpha: false, depth: false, stencil: false,
  powerPreference: 'low-power', preserveDrawingBuffer: false,
});

if (!gl) {
  document.body.classList.add('nogl');
  noteEl.textContent = 'This page needs WebGL2, which this browser does not offer.';
  noteEl.hidden = false;
  throw new Error('WebGL2 unavailable');
}

// ---- programs (compiled the first time each design is shown) ----------------
const vao = gl.createVertexArray();
const vs = compile(gl.VERTEX_SHADER, VERTEX);
const programs = new Map();

function compile(type, src) {
  const s = gl.createShader(type);
  gl.shaderSource(s, src);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(s) || 'shader compile failed');
  }
  return s;
}

function program(id) {
  if (programs.has(id)) return programs.get(id);
  const p = gl.createProgram();
  gl.attachShader(p, vs);
  gl.attachShader(p, compile(gl.FRAGMENT_SHADER, fragmentSource(id)));
  gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
    throw new Error(gl.getProgramInfoLog(p) || 'link failed');
  }
  const loc = (n) => gl.getUniformLocation(p, n);
  const entry = {
    p, time: loc('u_time'), aspect: loc('u_aspect'), brightness: loc('u_brightness'),
    tint: loc('u_tint'), res: loc('u_res'),
  };
  programs.set(id, entry);
  return entry;
}

// ---- state -------------------------------------------------------------------
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
};

const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
let style = indexFromHash() ?? clampIndex(parseInt(store.get('drift.style') ?? '0', 10));
let animated = fixedTime === null && !reduceMotion.matches;
// Like the app, start somewhere different each visit so it never looks the same twice.
const offset = fixedTime ?? Math.random() * 4000;
let clock = 0;            // seconds of animation so far (wall-clock, before SPEED)
let lastTick = null;
// Drawable pixels per CSS pixel; ?dpr= overrides it.
let scale = parseFloat(params.get('dpr')) || Math.min(window.devicePixelRatio || 1, 2);
let needsDraw = true;

function clampIndex(i) { return Number.isFinite(i) ? Math.min(Math.max(i, 0), WALLPAPERS.length - 1) : 0; }
function indexFromHash() {
  const i = WALLPAPERS.findIndex((w) => w.id === location.hash.slice(1).toLowerCase());
  return i >= 0 ? i : null;
}
function now() { return offset + clock * SPEED; }

// ---- picker ------------------------------------------------------------------
WALLPAPERS.forEach((w, i) => {
  const b = document.createElement('button');
  b.type = 'button';
  b.className = 'chip';
  b.textContent = w.name;
  b.setAttribute('role', 'radio');
  b.title = `${w.name} (${i + 1})`;
  b.addEventListener('click', () => select(i));
  picker.appendChild(b);
});

function select(i, { fromHash = false } = {}) {
  style = (i + WALLPAPERS.length) % WALLPAPERS.length;
  const w = WALLPAPERS[style];
  store.set('drift.style', String(style));
  if (!fromHash) history.replaceState(null, '', `${location.pathname}${location.search}#${w.id}`);
  nameEl.textContent = w.name;
  blurbEl.textContent = w.blurb;
  document.title = `Drift · ${w.name}`;
  [...picker.children].forEach((b, j) => {
    b.setAttribute('aria-checked', String(j === style));
    b.tabIndex = j === style ? 0 : -1;
  });
  picker.children[style].scrollIntoView({ block: 'nearest', inline: 'nearest' });
  needsDraw = true;
}

function setAnimated(on) {
  animated = on;
  playBtn.setAttribute('aria-pressed', String(on));
  playBtn.setAttribute('aria-label', on ? 'Pause' : 'Play');
  playBtn.title = on ? 'Pause (space)' : 'Play (space)';
  lastTick = null;
  needsDraw = true;
}

playBtn.addEventListener('click', () => setAnimated(!animated));
document.getElementById('prev').addEventListener('click', () => select(style - 1));
document.getElementById('next').addEventListener('click', () => select(style + 1));

function toggleFullscreen() {
  if (document.fullscreenElement) document.exitFullscreen?.();
  else document.documentElement.requestFullscreen?.().catch(() => {});
}
fsBtn.addEventListener('click', toggleFullscreen);
if (!document.documentElement.requestFullscreen) fsBtn.hidden = true;
document.addEventListener('fullscreenchange', () => {
  fsBtn.setAttribute('aria-pressed', String(!!document.fullscreenElement));
  poke();
});

window.addEventListener('hashchange', () => {
  const i = indexFromHash();
  if (i !== null && i !== style) select(i, { fromHash: true });
});

reduceMotion.addEventListener?.('change', (e) => { if (e.matches) setAnimated(false); });

window.addEventListener('keydown', (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  const k = e.key;
  if (k === 'ArrowRight' || k === 'ArrowDown') select(style + 1);
  else if (k === 'ArrowLeft' || k === 'ArrowUp') select(style - 1);
  else if (k >= '1' && k <= '9') select(Number(k) - 1);
  else if (k === ' ' && !(e.target instanceof HTMLButtonElement)) setAnimated(!animated);
  else if (k === 'f' || k === 'F') toggleFullscreen();
  else if (k === 'h' || k === 'H') document.body.classList.toggle('hide-ui');
  else return;
  e.preventDefault();
  poke();
});

// ---- controls fade out when the pointer rests, like a real wallpaper ----------
let idleTimer = 0;
function poke() {
  document.body.classList.remove('idle');
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    if (!ui.matches(':hover') && !ui.contains(document.activeElement)) document.body.classList.add('idle');
    else poke();
  }, 3500);
}
['pointermove', 'pointerdown', 'focusin'].forEach((ev) => window.addEventListener(ev, poke, { passive: true }));

// ---- render loop: 30 fps, paused when the tab is hidden, as in the app --------
function resize() {
  const w = Math.max(1, Math.round(canvas.clientWidth * scale));
  const h = Math.max(1, Math.round(canvas.clientHeight * scale));
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w;
    canvas.height = h;
    needsDraw = true;
  }
}
new ResizeObserver(resize).observe(canvas);

function draw() {
  resize();
  const e = program(WALLPAPERS[style].id);
  gl.viewport(0, 0, canvas.width, canvas.height);
  gl.useProgram(e.p);
  gl.uniform1f(e.time, now());
  gl.uniform1f(e.aspect, canvas.width / Math.max(canvas.height, 1));
  gl.uniform1f(e.brightness, BRIGHTNESS);
  gl.uniform4f(e.tint, TINT[0], TINT[1], TINT[2], 1);
  gl.uniform2f(e.res, canvas.width, canvas.height);
  gl.bindVertexArray(vao);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
  needsDraw = false;
}

// If frames keep arriving late, render fewer pixels rather than stutter.
const slow = { n: 0, late: 0 };
function adapt(dt) {
  slow.n++;
  if (dt > 1.6 / FPS) slow.late++;
  if (slow.n < 90) return;
  if (slow.late > 45 && scale > 0.6) {
    scale = Math.max(0.6, scale * 0.8);
    resize();
  }
  slow.n = slow.late = 0;
}

const frameGap = 1000 / FPS;
let lastFrame = 0;
function loop(ts) {
  requestAnimationFrame(loop);
  if (document.hidden) { lastTick = null; return; }
  if (animated) {
    if (ts - lastFrame < frameGap - 2) return;
    if (lastTick !== null) {
      const dt = Math.min((ts - lastTick) / 1000, 0.25);
      clock += dt;
      adapt(dt);
    }
    lastTick = ts;
    lastFrame = ts;
    draw();
  } else if (needsDraw) {
    draw();
  }
}

canvas.addEventListener('webglcontextlost', (e) => e.preventDefault());
canvas.addEventListener('webglcontextrestored', () => location.reload());

select(style, { fromHash: indexFromHash() !== null });
setAnimated(animated);
if (fixedTime === null && reduceMotion.matches) {
  noteEl.textContent = 'Paused because your system prefers reduced motion. Press play to animate.';
  noteEl.hidden = false;
}
poke();
draw();                    // first frame right away, without waiting for rAF
requestAnimationFrame(loop);

// Expose a tiny hook for automated checks.
window.drift = { select, setAnimated, draw, get style(){ return WALLPAPERS[style].id; }, get time() { return now(); } };
