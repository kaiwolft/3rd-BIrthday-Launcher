// The 3rd Birthday — Dionixu's Launcher (Electron / Chromium) · Windows y Linux
// Basado en el launcher de Pandora's Tower: lanza PPSSPP portable, aplica el parche al español de forma nativa
// (xdelta sobre la ISO americana o europea del usuario), ajustes, controles Xbox/teclado/ratón, motor de mods y pausa con F1 / L3+R3.
const { app, BrowserWindow, ipcMain, screen, protocol, net, session, shell } = require('electron');
const os = require('os');
const { pathToFileURL } = require('url');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { spawn } = require('child_process');

const IS_WIN = process.platform === 'win32';
const IS_LINUX = process.platform === 'linux';
const NL = IS_WIN ? '\r\n' : '\n';
const APP_NAME = "The 3rd Birthday — Dionixu's Launcher";
const ROOT = path.dirname(process.execPath);          // carpeta launcher
const PROJ = path.resolve(ROOT, '..');                // carpeta del proyecto
const UI = path.join(ROOT, 'ui');
const DATA = path.join(ROOT, 'data');
const CFG = path.join(DATA, 'config.json');
const PATHS = path.join(DATA, 'paths.json');
const HASHES = path.join(DATA, 'isos.json');
const LOG = path.join(DATA, 'launcher.log');

// Volcados conocidos (Redump; la española es la traducción UNDUB generada por el parche)
const KNOWN = {
  '47a7cb8e9e73d8aabef8139db7ee522b': { kind: 'us', id: 'ULUS10567', name: 'USA' },
  'd7c2309da1fb349b8dfce11f1b6c90a7': { kind: 'eu', id: 'ULES01513', name: 'Europa' },
  '688cc34138a19441044bce3d3a4c429b': { kind: 'jp', id: 'ULJM05798', name: 'Japón' },
  'c0e56a15c0d92450bdb1be09426b7300': { kind: 'es', id: 'ULES01513', name: 'Español (UNDUB)' }
};
const GAME_IDS = ['ULUS10567', 'ULES01513', 'ULJM05798'];

app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');
// Linux: que Chromium elija X11 o Wayland (forzar X11 bajo Wayland deja la ventana invisible)
if (IS_LINUX) app.commandLine.appendSwitch('ozone-platform-hint', 'auto');
protocol.registerSchemesAsPrivileged([{ scheme: 'pt', privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true } }]);
app.setPath('userData', path.join(DATA, 'chromium'));
app.setName("Dionixu's Launcher");

const log = (s) => { try { fs.appendFileSync(LOG, new Date().toISOString() + '  ' + s + '\n'); } catch (e) {} };
// Nunca mostrar el cuadro "A JavaScript error occurred in the main process": se anota en launcher.log y se sigue.
process.on('uncaughtException', (e) => log('ERROR no capturado: ' + (e && e.stack || e)));
process.on('unhandledRejection', (e) => log('Promesa rechazada: ' + (e && e.stack || e)));
const alive = (w) => !!(w && !w.isDestroyed());
const readJson = (f, d) => { try { return JSON.parse(fs.readFileSync(f, 'utf8').replace(/^﻿/, '')); } catch (e) { return d; } };
const exists = (f) => { try { return fs.existsSync(f); } catch (e) { return false; } };
const saveCfg = () => { try { fs.mkdirSync(DATA, { recursive: true }); fs.writeFileSync(CFG, JSON.stringify(cfg, null, 1)); } catch (e) {} };

let win = null, game = null, exitWin = null, bridge = null, exitOpen = false, gameStart = 0, busy = false;
let cfg = readJson(CFG, {});

// ---------------- rutas (absolutas o relativas a la carpeta del launcher)
// PPSSPP en Linux: Flatpak (org.ppsspp.PPSSPP) o el binario del sistema (PPSSPPSDL / ppsspp / PPSSPPQt)
const FLATPAK_ID = 'org.ppsspp.PPSSPP';
const which = (cmd) => (process.env.PATH || '').split(IS_WIN ? ';' : ':').map((d) => path.join(d, cmd)).find((p) => exists(p)) || null;
function linuxPpsspp() {
  for (const b of ['/var/lib/flatpak/app/' + FLATPAK_ID, path.join(os.homedir(), '.local/share/flatpak/app', FLATPAK_ID)]) if (exists(b)) return 'flatpak:' + FLATPAK_ID;
  return which('PPSSPPSDL') || which('ppsspp') || which('PPSSPPQt') || which('ppsspp-sdl') || null;
}
const paths = (() => {
  const raw = readJson(PATHS, {});
  const abs = (p) => path.resolve(ROOT, p);
  const pp = raw.ppsspp ? (String(raw.ppsspp).startsWith('flatpak:') ? raw.ppsspp : abs(raw.ppsspp))
    : IS_WIN ? abs('../PPSSPP/PPSSPPWindows64.exe') : (linuxPpsspp() || abs('../PPSSPP/PPSSPPSDL'));
  const out = {
    ppsspp: pp,
    // también la carpeta del proyecto (ISOs sueltas, p. ej. la japonesa)
    isoDirs: [...new Set((raw.isoDirs || ['../juego', '../originales', '../The 3rd Birthday(PSP)/juego']).concat('..').map(abs))],
    isoFiles: (raw.isoFiles || []).map(abs),   // ISOs que el instalador dejó en su sitio (sin copiar)
    patchDir: abs(raw.patchDir || '../parche'),
    xdelta: raw.xdelta ? abs(raw.xdelta) : IS_WIN ? abs('../herramientas/xdelta3.exe')
      : (exists(abs('../herramientas/xdelta3')) ? abs('../herramientas/xdelta3') : (which('xdelta3') || abs('../herramientas/xdelta3'))),
    cache: abs(raw.cache || '../cache'),
    mods: abs(raw.mods || '../mods')
  };
  // memstick: Windows = PPSSPP portable; Linux Flatpak = su carpeta de config; Linux binario = carpeta propia junto al juego
  out.flatpak = String(out.ppsspp).startsWith('flatpak:');
  out.xdgHome = abs(raw.xdgHome || '../ppsspp-user');
  out.memstick = raw.memstick ? abs(raw.memstick) : IS_WIN ? path.join(path.dirname(out.ppsspp), 'memstick')
    : out.flatpak ? path.join(os.homedir(), '.var', 'app', FLATPAK_ID, 'config', 'ppsspp') : path.join(out.xdgHome, 'ppsspp');
  out.system = path.join(out.memstick, 'PSP', 'SYSTEM');
  out.textures = path.join(out.memstick, 'PSP', 'TEXTURES');
  out.cheats = path.join(out.memstick, 'PSP', 'Cheats');
  out.plugins = path.join(out.memstick, 'PSP', 'PLUGINS');
  out.esIso = path.join(out.cache, 'T3B_ES.iso');
  out.saves = path.join(out.memstick, 'PSP', 'SAVEDATA');
  out.shots = path.join(out.memstick, 'PSP', 'SCREENSHOT');
  return out;
})();
const send = (type, data) => { try { if (alive(win)) win.webContents.send('msg', JSON.stringify({ type, data })); } catch (e) {} };

// ---------------- ISOs: se identifican por MD5 (se guarda en caché por ruta + tamaño + fecha)
let hashCache = readJson(HASHES, {});
function md5File(file, onPct) {
  return new Promise((ok, fail) => {
    const h = crypto.createHash('md5'), size = fs.statSync(file).size; let done = 0, last = 0;
    fs.createReadStream(file, { highWaterMark: 4 << 20 })
      .on('data', (b) => { h.update(b); done += b.length; const p = Math.floor(done * 100 / size); if (onPct && p !== last) { last = p; onPct(p); } })
      .on('end', () => ok(h.digest('hex'))).on('error', fail);
  });
}
async function identify(file, onPct) {
  const st = fs.statSync(file), key = file.toLowerCase();
  const c = hashCache[key];
  if (c && c.size === st.size && c.mtime === st.mtimeMs) return c.md5;
  const md5 = await md5File(file, onPct);
  hashCache[key] = { size: st.size, mtime: st.mtimeMs, md5 };
  try { fs.writeFileSync(HASHES, JSON.stringify(hashCache, null, 1)); } catch (e) {}
  return md5;
}
let isos = [];   // [{ file, md5, kind, id, name }]
async function scanIsos() {
  const files = [];
  for (const d of paths.isoDirs) {
    if (!exists(d)) continue;
    for (const f of fs.readdirSync(d)) if (/\.iso$/i.test(f) && !files.includes(path.join(d, f))) files.push(path.join(d, f));
  }
  for (const f of paths.isoFiles) if (exists(f) && !files.includes(f)) files.push(f);
  if (exists(paths.esIso)) files.push(paths.esIso);
  const out = [];
  for (const f of files) {
    try {
      const md5 = await identify(f, (p) => send('scan', { file: path.basename(f), pct: p }));
      const k = KNOWN[md5];
      out.push(Object.assign({ file: f, md5, kind: k ? k.kind : 'unknown', id: k ? k.id : '?', name: k ? k.name : 'Desconocida' }));
      log('ISO ' + (k ? k.name : 'desconocida') + ': ' + f + ' (' + md5 + ')');
    } catch (e) { log('ISO ' + f + ': ' + e.message); }
  }
  isos = out;
  return out;
}
const isoOf = (kind) => isos.find((i) => i.kind === kind);
const receta = () => readJson(path.join(paths.patchDir, 'receta.json'), null);
// Fuente desde la que se puede generar la versión en español (USA o Europa con su parche)
function patchSource() {
  const r = receta(); if (!r || !Array.isArray(r.fuentes)) return null;
  for (const f of r.fuentes) {
    const iso = isos.find((i) => i.md5 === String(f.md5_origen).toLowerCase());
    const px = path.join(paths.patchDir, f.parche);
    if (iso && exists(px)) return { iso, patch: px, dest: r.destino };
  }
  return null;
}
function versions() {
  const src = patchSource();
  return {
    es: !!isoOf('es') || !!src,
    esReady: !!isoOf('es'),
    esSource: src ? src.iso.name : null,
    en: !!(isoOf('us') || isoOf('eu')),
    jp: !!isoOf('jp'),
    xdelta: exists(paths.xdelta)
  };
}

// Partidas guardadas de PPSSPP (SAVEDATA\<ID>...) y capturas (SCREENSHOT\*.png|jpg)
function savesInfo() {
  const out = { count: 0, last: 0 };
  try {
    for (const d of fs.readdirSync(paths.saves, { withFileTypes: true })) {
      if (!d.isDirectory() || !GAME_IDS.some((id) => d.name.toUpperCase().startsWith(id))) continue;
      out.count++;
      for (const f of fs.readdirSync(path.join(paths.saves, d.name))) {
        try { const m = fs.statSync(path.join(paths.saves, d.name, f)).mtimeMs; if (m > out.last) out.last = m; } catch (e) {}
      }
    }
  } catch (e) {}
  return out;
}
function shotList() {
  const out = [];
  const walk = (dir, rel) => {
    let es = []; try { es = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return; }
    for (const e of es) {
      const r = rel ? rel + '/' + e.name : e.name;
      if (e.isDirectory()) walk(path.join(dir, e.name), r);
      else if (/\.(png|jpe?g)$/i.test(e.name)) { try { out.push({ f: r, t: fs.statSync(path.join(dir, e.name)).mtimeMs }); } catch (x) {} }
    }
  };
  walk(paths.shots, '');
  return out.sort((a, b) => b.t - a.t).slice(0, 48);
}

function state() {
  const r = receta();
  return {
    config: cfg,
    fullscreen: !!(win && win.isFullScreen()),
    ppssppOk: ppOk(),
    platform: process.platform,
    isos: isos.map((i) => ({ name: i.name, kind: i.kind, id: i.id, file: path.basename(i.file) })),
    versions: versions(),
    buttons: { xbox: true, kb: true },
    mods: listMods(),
    saves: savesInfo(),
    shots: shotList(),
    patchFrom: r && Array.isArray(r.fuentes) ? r.fuentes.map((f) => f.region) : []
  };
}

// ---------------- parche nativo: original (USA/EU) + xdelta -> cache\T3B_ES.iso, verificado por MD5
let patching = null;
async function buildSpanish() {
  if (isoOf('es')) return isoOf('es');
  if (patching) return patching;
  patching = (async () => {
    const src = patchSource();
    if (!src) throw new Error('Para la versión en español hace falta tu ISO americana o europea original y el parche (carpeta parche).');
    if (!exists(paths.xdelta)) throw new Error(IS_WIN ? 'Falta herramientas\\xdelta3.exe' : 'Falta xdelta3 (instala el paquete xdelta3 de tu distribución)');
    fs.mkdirSync(paths.cache, { recursive: true });
    const tmp = paths.esIso + '.tmp';
    try { fs.rmSync(tmp, { force: true }); } catch (e) {}
    log('Parche: ' + src.iso.file + ' + ' + src.patch);
    send('patch', { phase: 'apply', pct: 0, from: src.iso.name });
    await new Promise((ok, fail) => {
      const p = spawn(paths.xdelta, ['-d', '-f', '-B', '1073741824', '-s', src.iso.file, src.patch, tmp], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
      let err = ''; p.stderr.on('data', (d) => { err += d; });
      const t = setInterval(() => { try { const s = fs.statSync(tmp).size; send('patch', { phase: 'apply', pct: Math.min(99, Math.floor(s * 100 / src.dest.bytes)), from: src.iso.name }); } catch (e) {} }, 500);
      p.on('error', (e) => { clearInterval(t); fail(e); });
      p.on('exit', (code) => { clearInterval(t); code === 0 ? ok() : fail(new Error('xdelta3 terminó con código ' + code + ' ' + err.slice(0, 300))); });
    });
    send('patch', { phase: 'verify', pct: 0 });
    const md5 = await md5File(tmp, (pct) => send('patch', { phase: 'verify', pct }));
    if (md5 !== String(src.dest.md5).toLowerCase()) { fs.rmSync(tmp, { force: true }); throw new Error('La ISO en español no pasó la verificación (MD5 ' + md5 + ')'); }
    fs.renameSync(tmp, paths.esIso);
    const st = fs.statSync(paths.esIso);
    hashCache[paths.esIso.toLowerCase()] = { size: st.size, mtime: st.mtimeMs, md5 };
    try { fs.writeFileSync(HASHES, JSON.stringify(hashCache, null, 1)); } catch (e) {}
    log('Parche aplicado y verificado: ' + paths.esIso);
    const es = { file: paths.esIso, md5, kind: 'es', id: 'ULES01513', name: KNOWN[md5].name };
    isos = isos.filter((i) => i.kind !== 'es').concat(es);
    send('patch', { phase: 'done', pct: 100 });
    return es;
  })();
  try { return await patching; } finally { patching = null; }
}

// ---------------- .ini de PPSSPP: editar claves conservando el resto
function setIni(file, values) {
  let text = '';
  try { text = fs.readFileSync(file, 'utf8').replace(/^﻿/, ''); } catch (e) {}
  const lines = text.split(/\r?\n/);
  for (const [section, entries] of Object.entries(values)) {
    let start = lines.findIndex((l) => l.trim().toLowerCase() === '[' + section.toLowerCase() + ']');
    if (start < 0) { if (lines.length && lines[lines.length - 1] !== '') lines.push(''); lines.push('[' + section + ']'); start = lines.length - 1; }
    for (const [key, val] of Object.entries(entries)) {
      let end = lines.findIndex((l, i) => i > start && /^\s*\[/.test(l)); if (end < 0) end = lines.length;
      const i = lines.findIndex((l, j) => j > start && j < end && l.split('=')[0].trim().toLowerCase() === key.toLowerCase());
      const line = key + ' = ' + val;
      if (i >= 0) lines[i] = line; else lines.splice(end, 0, line);
    }
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, lines.join(NL).replace(/(\r?\n)+$/, '') + NL);
}

// ---------------- controles (PPSSPP controls.ini: "Botón = dispositivo-código, ...")
// Dispositivos: 1 teclado, 2 ratón, 10 mando DirectInput/SDL, 20 mando XInput (Xbox). Códigos tipo Android (NKCODE);
// ejes = 4000 + eje*2 (+1 si es negativo). Posición PlayStation: aceptar (Cruz) = A de Xbox.
const PADCODE = { 'Button A': 96, 'Button B': 97, 'Button X': 99, 'Button Y': 100, 'Shoulder L': 102, 'Shoulder R': 103,
  'Trigger L': 4034, 'Trigger R': 4036, Back: 109, Start: 108, 'Thumb L': 106, 'Thumb R': 107, 'Pad N': 19, 'Pad S': 20, 'Pad W': 21, 'Pad E': 22 };
const KEYCODE = { SPACE: 62, LSHIFT: 59, RSHIFT: 60, LCONTROL: 113, RCONTROL: 114, LMENU: 57, RMENU: 58, RETURN: 66, NUMPADENTER: 160, ESCAPE: 111,
  TAB: 61, BACK: 67, CAPITAL: 115, UP: 19, DOWN: 20, LEFT: 21, RIGHT: 22, MINUS: 69, EQUALS: 70, LBRACKET: 71, RBRACKET: 72, SEMICOLON: 74,
  APOSTROPHE: 75, GRAVE: 68, BACKSLASH: 73, OEM_102: 73, COMMA: 55, PERIOD: 56, SLASH: 76, INSERT: 124, DELETE: 112, HOME: 122, END: 123,
  PRIOR: 92, NEXT: 93, ADD: 157, SUBTRACT: 156, MULTIPLY: 155, DIVIDE: 154, DECIMAL: 158 };
const MOUSECODE = { 'Click 0': 1002, 'Click 1': 1003, 'Click 2': 1004, 'Click 3': 1005, 'Click 4': 1006, 'Axis Z+': 1008, 'Axis Z-': 1009 };
const keyCode = (n) => {
  let m;
  if (KEYCODE[n] != null) return '1-' + KEYCODE[n];
  if (MOUSECODE[n] != null) return '2-' + MOUSECODE[n];
  if ((m = /^[A-Z]$/.exec(n))) return '1-' + (29 + n.charCodeAt(0) - 65);
  if ((m = /^[0-9]$/.exec(n))) return '1-' + (7 + +n);
  if ((m = /^F(\d{1,2})$/.exec(n))) return '1-' + (130 + +m[1]);
  if ((m = /^NUMPAD(\d)$/.exec(n))) return '1-' + (144 + +m[1]);
  return null;
};
const padCode = (n) => PADCODE[n] != null ? ['20-' + PADCODE[n], '10-' + PADCODE[n]] : [];
// Acciones PSP y valores por defecto (The 3rd Birthday: L apuntar, R disparar, Triángulo Overdive)
const PAD_DEF = { cross: 'Button A', circle: 'Button B', square: 'Button X', triangle: 'Button Y', l: 'Trigger L', r: 'Trigger R',
  start: 'Start', select: 'Back', du: 'Pad N', dd: 'Pad S', dl: 'Pad W', dr: 'Pad E' };
const PAD_EXTRA = { l: 'Shoulder L', r: 'Shoulder R' };   // LB/RB también apuntan/disparan
const KB_DEF = { ls_up: 'W', ls_down: 'S', ls_left: 'A', ls_right: 'D', rs_up: 'I', rs_down: 'K', rs_left: 'J', rs_right: 'L',
  cross: 'SPACE', circle: 'LSHIFT', square: 'R', triangle: 'Q', l: 'Click 1', r: 'Click 0', start: 'RETURN', select: 'TAB',
  du: 'UP', dd: 'DOWN', dl: 'LEFT', dr: 'RIGHT' };
const okName = (v) => typeof v === 'string' && /^[A-Za-z0-9 +\-_.]{1,24}$/.test(v);
function writeControls() {
  const pb = Object.assign({}, PAD_DEF, cfg.padBinds || {}), kb = Object.assign({}, KB_DEF, cfg.kbBinds || {});
  const used = new Set(Object.values(kb));
  const k = (n) => okName(n) && n !== 'ESCAPE' && n !== 'F1' ? keyCode(n) : null;   // ESC = pausa del launcher
  const join = (...a) => [...new Set(a.flat().filter(Boolean))].join(',');
  const btn = (id) => join(padCode(pb[id]), id in PAD_EXTRA && !Object.values(pb).includes(PAD_EXTRA[id]) ? padCode(PAD_EXTRA[id]) : [], k(kb[id]),
    id === 'cross' && !used.has('RETURN') ? k('RETURN') : null);
  const inv = cfg.padInvert === 'on';
  const mouseCam = cfg.kbCam !== 'keys';
  const L = ['[ControlMapping]',
    'Up = ' + btn('du'), 'Down = ' + btn('dd'), 'Left = ' + btn('dl'), 'Right = ' + btn('dr'),
    'Circle = ' + btn('circle'), 'Cross = ' + btn('cross'), 'Square = ' + btn('square'), 'Triangle = ' + btn('triangle'),
    'Start = ' + btn('start'), 'Select = ' + btn('select'), 'L = ' + btn('l'), 'R = ' + btn('r'),
    // XInput: eje Y hacia arriba = positivo (4002); DirectInput: hacia arriba = negativo (4003)
    'An.Up = ' + join('20-4002', '10-4003', k(kb.ls_up)), 'An.Down = ' + join('20-4003', '10-4002', k(kb.ls_down)),
    'An.Left = ' + join('20-4001', '10-4001', k(kb.ls_left)), 'An.Right = ' + join('20-4000', '10-4000', k(kb.ls_right)),
    // stick derecho: lo leen los plugins (cámara libre); ratón = movimiento relativo (ejes 26/27)
    'RightAn.Up = ' + join(inv ? '20-4029' : '20-4028', mouseCam ? (cfg.invert === 'on' ? '2-4054' : '2-4055') : k(kb.rs_up)),
    'RightAn.Down = ' + join(inv ? '20-4028' : '20-4029', mouseCam ? (cfg.invert === 'on' ? '2-4055' : '2-4054') : k(kb.rs_down)),
    'RightAn.Left = ' + join('20-4023', mouseCam ? '2-4053' : k(kb.rs_left)),
    'RightAn.Right = ' + join('20-4022', mouseCam ? '2-4052' : k(kb.rs_right)),
    // el menú propio de PPSSPP queda en F12 (ESC abre la pausa del launcher)
    'Pause = 1-142', 'Screenshot = 1-139'];
  const file = path.join(paths.system, 'controls.ini');
  if (cfg.autoControls === 'off') { log('Controles: se conserva controls.ini de PPSSPP'); return; }
  fs.mkdirSync(paths.system, { recursive: true });
  fs.writeFileSync(file, L.join(NL) + NL);
}

// ---------------- botones dentro del juego + texturas HD (TEXTURES\<ID>\botones + textures.ini generado)
// Bases HD x4 (ui\assets\botones) sacadas de los volcados de ULES01513: fuente (dos paletas) y atlas del HUD.
// Los iconos Xbox / teclado-ratón se dibujan con ui\botones.html en una ventana oculta según los controles actuales.
const GLYPH_VER = 5;
// Juegos de texturas por versión (hash volcado por PPSSPP -> archivo). glyph = llevan iconos de botones (se redibujan), hd = solo HD.
// Bases HD en ui\assets\botones (es) y ui\assets\botones\us. Se instalan ambas en cada juego: vale la que coincida.
const TEXSETS = [
  { dir: 'es', base: '', lang: 'es', aviso: [208, 72, 12, 12],
    glyph: [['0998048021b90c72aff9c741', 'fuente_a.png'], ['099804806e408c26aff9c741', 'fuente_b.png'], ['08ce4da0c05252b9fadd3775', 'hud.png'], ['08ce20e028333f3153a656a7', 'aviso.png']],
    hd: [['09c5d38021b903728fef25a6', 'fuente2_a.png'], ['09c5d3806e4083268fef25a6', 'fuente2_b.png'], ['09c63c0021b90272f396c2af', 'fuente3_a.png'], ['09c63c006e408226f396c2af', 'fuente3_b.png']] },
  { dir: 'us', base: 'us', lang: 'en', aviso: [225, 72, 12, 12],
    glyph: [['09973c8021b90c722128ceb2', 'fuente_a.png'], ['09973c806e408c262128ceb2', 'fuente_b.png'], ['08ce4da0f75bf2e1358b383d', 'hud.png'], ['08ce20e0482166f676a926dd', 'aviso.png']],
    hd: [['09c6238021b9017217ea854f', 'fuente2_a.png'], ['09c623806e40812617ea854f', 'fuente2_b.png'], ['09c64c0021b9017240e68a53', 'fuente3_a.png'], ['09c64c006e40812640e68a53', 'fuente3_b.png']] },
  // japonesa: la fuente va en 3 páginas; los iconos están en la 3.ª (0x09961a80, 512x128, con basura variable al final ->
  // [hashranges] solo 96 filas -> 09961a8021b9037233f4e3ad). Falta la paleta con contorno (6e40) y el HUD: no salieron en los volcados.
  { dir: 'jp', base: 'jp', lang: 'en', aviso: [225, 72, 12, 12], avisoAct: 'circle', hud: false, ids: ['ULJM05798'],
    ranges: ['0x09961a80,512,128 = 512,96'],
    cells: { square: [187, 51, 17], triangle: [204, 51, 17], circle: [221, 51, 17], cross: [238, 51, 17], ls: [255, 51, 17], rs: [272, 51, 17],
      du: [289, 51, 17], dd: [306, 51, 17], dl: [323, 51, 17], dr: [340, 51, 17], l: [357, 51, 34], r: [391, 51, 34], select: [425, 51, 51], start: [0, 68, 51] },
    glyph: [['08ce16e085af7cf3d075151e', 'aviso.png'], ['09961a8021b9037233f4e3ad', 'fuente_a.png'], [null, 'fuente_b.png']],
    hd: [['09921a8021b90d7215d5285d', 'fuente2_a.png'], ['09921a8021b90d7253583b63', 'fuente2_a.png'], ['09921a806e408d2615d5285d', 'fuente2_b.png'], ['09921a806e408d2653583b63', 'fuente2_b.png'],
      ['09941a8021b90d7211a6a376', 'fuente4_a.png'], ['09941a8021b90d727b8943eb', 'fuente4_a.png'], ['09941a8021b90d7281beb8d9', 'fuente4_a.png'],
      ['09c65a0021b9017240e70253', 'fuente3_a.png'], ['09c65a006e40812640e70253', 'fuente3_b.png']] }];
const TEX_MARK = '# The 3rd Birthday - generado por el launcher';
async function renderGlyphs(opts) {
  const w = new BrowserWindow({ show: false, width: 64, height: 64, webPreferences: { sandbox: true, contextIsolation: true, nodeIntegration: false, backgroundThrottling: false } });
  try {
    await w.loadURL('pt://ui/botones.html');
    return await w.webContents.executeJavaScript('buildGlyphs(' + JSON.stringify(opts) + ')', true);
  } finally { if (!w.isDestroyed()) w.destroy(); }
}
async function glyphFiles(iconSet, set) {
  const which = iconSet === 'kb' ? 'kb' : 'xbox';
  const opts = { set: which, lang: set.lang, dir: set.base, aviso: set.aviso, avisoAct: set.avisoAct, hud: set.hud, cells: set.cells, mouseCam: cfg.kbCam !== 'keys',
    pad: Object.assign({}, PAD_DEF, cfg.padBinds || {}), keys: Object.assign({}, KB_DEF, cfg.kbBinds || {}) };
  const sig = require('crypto').createHash('sha1').update(JSON.stringify([GLYPH_VER, opts])).digest('hex').slice(0, 12);
  const cache = path.join(DATA, 'botones', 'cache'), dir = path.join(cache, set.dir + '_' + which + '_' + sig);
  if (set.glyph.every(([, f]) => exists(path.join(dir, f)))) return dir;
  const out = await renderGlyphs(opts);
  fs.mkdirSync(dir, { recursive: true });
  for (const [, f] of set.glyph) {
    const data = out[f.replace('.png', '')];
    if (!data) throw new Error('falta ' + f);
    fs.writeFileSync(path.join(dir, f), Buffer.from(data.split(',')[1], 'base64'));
  }
  // conserva solo las 8 más recientes
  try {
    const old = fs.readdirSync(cache).map((n) => ({ n, t: fs.statSync(path.join(cache, n)).mtimeMs })).sort((a, b) => b.t - a.t).slice(8);
    for (const o of old) fs.rmSync(path.join(cache, o.n), { recursive: true, force: true });
  } catch (e) {}
  log('Botones: iconos ' + which + ' (' + set.dir + ') dibujados');
  return dir;
}
const copyIfChanged = (a, b) => {
  try { const sa = fs.statSync(a), sb = fs.statSync(b); if (sa.size === sb.size && Math.abs(sb.mtimeMs - sa.mtimeMs) < 2) return; } catch (e) {}
  fs.copyFileSync(a, b);
};
async function applyButtons(iconSet, gameId) {
  const srcs = {};
  if (cfg.hdTex !== 'off') for (const set of TEXSETS) {
    const base = path.join(UI, 'assets', 'botones', set.base);
    try { srcs[set.dir] = await glyphFiles(iconSet, set); } catch (e) { log('Botones (' + set.dir + '): ' + e.message + ' (originales HD)'); srcs[set.dir] = base; }
  }
  // solo en la carpeta del juego que se abre, y solo los archivos que cambiaron (antes se copiaban ~60 MB en cada inicio)
  for (const id of GAME_IDS) {
    const active = path.join(paths.textures, id, 'botones');
    if (id !== gameId || !Object.keys(srcs).length) { if (id === gameId) fs.rmSync(active, { recursive: true, force: true }); continue; }
    for (const set of TEXSETS) {
      const dst = path.join(active, set.dir), base = path.join(UI, 'assets', 'botones', set.base);
      if (set.ids && !set.ids.includes(id)) { fs.rmSync(dst, { recursive: true, force: true }); continue; }
      fs.mkdirSync(dst, { recursive: true });
      for (const [, f] of set.glyph) copyIfChanged(path.join(srcs[set.dir], f), path.join(dst, f));
      for (const [, f] of set.hd) copyIfChanged(path.join(base, f), path.join(dst, f));
    }
  }
  log('Botones: ' + (Object.keys(srcs).length ? (iconSet === 'kb' ? 'teclado' : 'xbox') + ' HD' : 'texturas originales'));
}
// textures.ini de cada juego: botones + mods + textures.user.ini (las del usuario se conservan aparte)
function writeTexturesIni(gameId, modTex) {
  for (const id of GAME_IDS) {
    const dir = path.join(paths.textures, id), file = path.join(dir, 'textures.ini'), user = path.join(dir, 'textures.user.ini');
    if (exists(file) && !fs.readFileSync(file, 'utf8').startsWith(TEX_MARK)) {
      if (!exists(user)) fs.renameSync(file, user); else fs.rmSync(file, { force: true });
      log('Texturas: tu textures.ini se guardó como textures.user.ini');
    }
    const H = [];
    const R = [];
    for (const set of TEXSETS) if (exists(path.join(dir, 'botones', set.dir)) && (!set.ids || set.ids.includes(id))) {
      for (const [h, f] of set.glyph.concat(set.hd)) if (h) H.push(h + ' = botones/' + set.dir + '/' + f, '00000000' + h.slice(8) + ' = botones/' + set.dir + '/' + f);
      R.push(...(set.ranges || []));
    }
    if (id === gameId) for (const [h, f] of modTex) H.push(h + ' = ' + f);
    const U = exists(user) ? parseIni(user) : {};
    const sec = (n) => U[Object.keys(U).find((k) => k.toLowerCase() === n)] || {};
    for (const [k, v] of Object.entries(sec('hashes'))) H.push(k + ' = ' + v);
    if (!H.length) { if (exists(file)) fs.rmSync(file, { force: true }); continue; }
    const L = [TEX_MARK + ' (se rehace en cada inicio). Tus propias entradas van en textures.user.ini', '[options]'];
    for (const [k, v] of Object.entries(Object.assign({ version: '1', hash: 'quick' }, sec('options')))) L.push(k + ' = ' + v);
    L.push('', '[hashes]', ...H);
    // [hashranges]: texturas con basura variable al final (solo se calcula el hash de la parte útil)
    const UR = sec('hashranges');
    if (R.length || Object.keys(UR).length) L.push('', '[hashranges]', ...R, ...Object.entries(UR).map(([k, v]) => k + ' = ' + v));
    for (const [n, kv] of Object.entries(U)) if (!/^(options|hashes|hashranges)$/i.test(n)) { L.push('', '[' + n + ']'); for (const [k, v] of Object.entries(kv)) L.push(k + ' = ' + v); }
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(file, L.join(NL) + NL);
  }
}

// ---------------- motor de mods: mods\<nombre>\mod.json + textures\ + cheats.ini + plugin\ + ppsspp.ini
function listMods() {
  if (!exists(paths.mods)) return [];
  const out = [];
  for (const d of fs.readdirSync(paths.mods, { withFileTypes: true })) {
    if (!d.isDirectory()) continue;
    const dir = path.join(paths.mods, d.name), j = readJson(path.join(dir, 'mod.json'), {});
    const parts = [];
    if (exists(path.join(dir, 'textures'))) parts.push('texturas');
    if (exists(path.join(dir, 'cheats.ini'))) parts.push('trucos');
    if (exists(path.join(dir, 'plugin'))) parts.push('plugin');
    if (exists(path.join(dir, 'ppsspp.ini'))) parts.push('ajustes');
    out.push({ id: d.name, name: j.name || d.name, description: j.description || '', author: j.author || '', version: j.version || '',
      parts, on: (cfg.mods || {})[d.name] === true || ((cfg.mods || {})[d.name] == null && j.enabled === true) });
  }
  return out;
}
const copyDir = (a, b) => { fs.mkdirSync(b, { recursive: true }); for (const e of fs.readdirSync(a, { withFileTypes: true })) { const s = path.join(a, e.name), t = path.join(b, e.name); e.isDirectory() ? copyDir(s, t) : fs.copyFileSync(s, t); } };
function applyMods(gameId, version) {
  const mods = listMods().filter((m) => m.on);
  // texturas: TEXTURES\<ID>\mods (se rehace en cada inicio)
  const tdir = path.join(paths.textures, gameId, 'mods');
  fs.rmSync(tdir, { recursive: true, force: true });
  // plugins: solo los instalados por el launcher (marcados con .t3b)
  if (exists(paths.plugins)) for (const p of fs.readdirSync(paths.plugins)) if (exists(path.join(paths.plugins, p, '.t3b'))) fs.rmSync(path.join(paths.plugins, p), { recursive: true, force: true });
  const cheats = [], ini = [], modTex = [];
  for (const m of mods) {
    const dir = path.join(paths.mods, m.id);
    try {
      if (m.parts.includes('texturas')) { copyDir(path.join(dir, 'textures'), path.join(tdir, m.id)); modTex.push(...modTextureEntries(path.join(dir, 'textures'), 'mods/' + m.id + '/')); }
      if (m.parts.includes('trucos')) cheats.push('// ' + m.name, fs.readFileSync(path.join(dir, 'cheats.ini'), 'utf8').trim());
      if (m.parts.includes('plugin')) { const t = path.join(paths.plugins, 't3b_' + m.id); copyDir(path.join(dir, 'plugin'), t); fs.writeFileSync(path.join(t, '.t3b'), ''); }
      if (m.parts.includes('ajustes')) ini.push(path.join(dir, 'ppsspp.ini'));
      log('Mod activo: ' + m.name);
    } catch (e) { log('Mod ' + m.id + ': ' + e.message); }
  }
  fs.mkdirSync(paths.cheats, { recursive: true });
  const cf = path.join(paths.cheats, gameId + '.ini');
  const fc = freecamOn() ? freecamCheat() : [];
  if (cheats.length || fc.length) {
    const head = ['// The 3rd Birthday - archivo generado por el launcher (se rehace en cada inicio)', '_S ' + gameId.slice(0, 4) + '-' + gameId.slice(4), '_G The 3rd Birthday'];
    fs.writeFileSync(cf, head.concat(fc, cheats).join(NL) + NL);
    if (fc.length) log('Cámara libre: truco escrito en ' + cf);
  } else if (exists(cf) && fs.readFileSync(cf, 'utf8').startsWith('// ')) fs.rmSync(cf, { force: true });
  return { cheats: cheats.length > 0 || fc.length > 0, ini, tex: modTex };
}
// entradas de textures.ini de un mod: su propio [hashes] (rutas relativas a su carpeta) o los .png con nombre de hash
function modTextureEntries(dir, prefix) {
  const out = [], ini = path.join(dir, 'textures.ini');
  if (exists(ini)) {
    const h = parseIni(ini).hashes || {};
    for (const [k, v] of Object.entries(h)) if (/^[0-9a-f]{16,24}$/i.test(k) && v) out.push([k, prefix + v.replace(/\\/g, '/')]);
    return out;
  }
  const walk = (d, rel) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    if (e.isDirectory()) walk(path.join(d, e.name), rel + e.name + '/');
    else { const m = /^([0-9a-f]{24})(?:_\d+)?\.(png|dds|ktx2|zim)$/i.exec(e.name); if (m) out.push([m[1], prefix + rel + e.name]); }
  } };
  walk(dir, '');
  return out;
}
// ---------------- cámara libre (versión en español, ULES01513 traducido)
// Truco CWCheat (v3, +0x110 = elevación de la mirada): rutina en 0x08800200 que, si está activa, coloca el ojo de la cámara en la dirección que manda el puente
// (0x08800104 = vector unitario) conservando la distancia del juego, y publica la dirección original en 0x08800130.
// La llamada del controlador de cámara del jugador a setEyeTarget (0x08AC16A0 -> 0x08B209CC) se desvía a la rutina.
const FREECAM_CODE = [0x3C080880, 0xC4A00000, 0xC4A10004, 0xC4A20008, 0xC4C30000, 0xC4C40004, 0xC4C50008, 0x46030001, 0x46040841,
  0x46051081, 0xE5000130, 0xE5010134, 0xE5020138, 0x8D090100, 0x1120001E, 0x00000000, 0x46000182, 0x460109C2,
  0x46073180, 0x460211C2, 0x46073180, 0x46003184, 0xC5070104, 0x460639C2, 0x460339C0, 0xE5070120, 0xC5080108,
  0x46064202, 0x46044200, 0xE5080124, 0xC509010C, 0x46064A42, 0x46054A40, 0xE5090128, 0x8CA9000C, 0xAD09012C,
  0x25050120, 0xC50A0110, 0x460A2100, 0xE5030140, 0xE5040144, 0xE5050148, 0x8CC9000C, 0xAD09014C, 0x25060140,
  0x0A2C8273, 0x00000000];
const hex8 = (n) => '0x' + (n >>> 0).toString(16).toUpperCase().padStart(8, '0');
// Versiones conocidas: llamada del controlador de cámara del jugador a setEyeTarget (site) y la función (fn), en RAM
// (módulo cargado en 0x08804000). Encontradas por firma de bytes en los ejecutables descifrados (ver PROYECTO_NOTAS.md).
const FREECAM_TARGETS = [
  { name: 'ES/USA', site: 0x08AC16A0, fn: 0x08B209CC },  // ULUS10567 y la traducción española (su EBOOT.OLD sale del ejecutable USA)
  { name: 'JP', site: 0x08AC0D68, fn: 0x08B20008 }        // ULJM05798
];
const jal = (a) => 0x0C000000 | ((a >>> 2) & 0x03FFFFFF), jmp = (a) => 0x08000000 | ((a >>> 2) & 0x03FFFFFF);
function freecamCheat() {
  const L = [];
  for (const t of FREECAM_TARGETS) {
    // 0xC = "si la llamada original no está ahí, para": solo se activa en la versión que coincide (y nunca escribe en otra)
    L.push('_C1 Camara libre (launcher) ' + t.name, '_L ' + hex8(0xC0000000 + (t.site - 0x08800000)) + ' ' + hex8(jal(t.fn)));
    FREECAM_CODE.forEach((w, i) => L.push('_L ' + hex8(0x20000200 + i * 4) + ' ' + hex8(i === FREECAM_CODE.length - 2 ? jmp(t.fn) : w)));
    L.push('_L ' + hex8(0x20000000 + (t.site - 0x08800000)) + ' ' + hex8(jal(0x08800200)));
  }
  return L;
}
const freecamOn = () => cfg.freecam !== 'off';
// nombre de tecla del launcher -> código virtual de Windows (para mover la cámara con teclas)
const vkOf = (n) => { let m; if (!n) return 0; if ((m = /^[A-Z]$/.exec(n))) return n.charCodeAt(0); if ((m = /^[0-9]$/.exec(n))) return 48 + +n;
  if ((m = /^NUMPAD(\d)$/.exec(n))) return 0x60 + +m[1]; return { UP: 0x26, DOWN: 0x28, LEFT: 0x25, RIGHT: 0x27, SPACE: 0x20, TAB: 0x09, LSHIFT: 0xA0, RSHIFT: 0xA1, LCONTROL: 0xA2,
  RCONTROL: 0xA3, 'Click 0': 0x01, 'Click 1': 0x02, 'Click 2': 0x04, 'Click 3': 0x05, 'Click 4': 0x06 }[n] || 0; };

// Lee un .ini simple a { seccion: { clave: valor } } (para los ajustes que traen los mods)
function parseIni(file) {
  const out = {}; let sec = null;
  for (const l of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const s = /^\s*\[(.+)\]\s*$/.exec(l); if (s) { sec = s[1]; out[sec] = out[sec] || {}; continue; }
    const kv = /^\s*([^=#;]+?)\s*=\s*(.*)$/.exec(l); if (kv && sec) out[sec][kv[1]] = kv[2];
  }
  return out;
}

// ---------------- aviso de logro (ventana transparente encima del juego, sin robar el foco)
let toastWin = null, toastQueue = [], toastBusy = false, toastSeq = 0;
function createToastWindow() {
  const d = screen.getPrimaryDisplay().bounds;
  toastWin = new BrowserWindow({
    x: d.x + Math.round((d.width - 620) / 2), y: d.y, width: 620, height: 150, show: false, frame: false, transparent: true,
    resizable: false, focusable: false, skipTaskbar: true, alwaysOnTop: true, fullscreenable: false, hasShadow: false, backgroundColor: '#00000000',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true, backgroundThrottling: false }
  });
  toastWin.setAlwaysOnTop(true, 'screen-saver');
  toastWin.setIgnoreMouseEvents(true);
  toastWin.setMenu(null);
  toastWin.loadURL('pt://ui/toast.html');
}
function showAchievement(a) {
  if (cfg.achToast === 'off') return;
  toastQueue.push(Object.assign({ lang: cfg.ui || 'es', sound: cfg.sfx !== 'off' }, a));
  nextToast();
}
function nextToast() {
  if (toastBusy || !toastQueue.length || !alive(toastWin)) return;
  toastBusy = true;
  const d = screen.getPrimaryDisplay().bounds;
  toastWin.setBounds({ x: d.x + Math.round((d.width - 620) / 2), y: d.y, width: 620, height: 150 });
  toastWin.showInactive();
  toastWin.setAlwaysOnTop(true, 'screen-saver');
  toastWin.webContents.send('msg', JSON.stringify({ type: 'show', data: toastQueue.shift() }));
  const id = ++toastSeq;
  setTimeout(() => { if (toastBusy && id === toastSeq) { toastBusy = false; nextToast(); } }, 9000);
}

// ---------------- puente de mando + menú de pausa
const sendExit = (type, data) => { try { if (alive(exitWin)) exitWin.webContents.send('msg', JSON.stringify({ type, data })); } catch (e) {} };
const bridgeCmd = (s) => { try { if (bridge && bridge.exitCode === null && bridge.stdin && bridge.stdin.writable && !bridge.stdin.destroyed) bridge.stdin.write(s + '\n', () => {}); } catch (e) {} };
const hwnd = (w) => { const b = w.getNativeWindowHandle(); return (b.length >= 8 ? b.readBigUInt64LE(0) : BigInt(b.readUInt32LE(0))).toString(); };

function createExitWindow() {
  const d = screen.getPrimaryDisplay().bounds;
  exitWin = new BrowserWindow({
    x: d.x, y: d.y, width: d.width, height: d.height, show: false, frame: false, transparent: true, resizable: false,
    skipTaskbar: true, alwaysOnTop: true, fullscreenable: false, hasShadow: false, backgroundColor: '#00000000',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true }
  });
  exitWin.setAlwaysOnTop(true, 'screen-saver');
  exitWin.setMenu(null);
  exitWin.loadURL('pt://ui/exit.html');
}
function startBridge() {
  stopBridge();
  if (!IS_WIN) return;   // el puente (foco, pausa con ESC, cámara libre, volumen) usa APIs de Windows
  bridge = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', path.join(__dirname, 'bridge.ps1')], { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] });
  // si el puente ya se cerró, escribirle da EPIPE: se ignora en vez de romper el launcher
  bridge.stdin.on('error', (e) => log('puente (stdin): ' + e.code));
  bridge.stdout.on('error', () => {});
  let buf = '';
  bridge.stdout.on('data', (d) => {
    buf += d.toString(); let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
      if (line.startsWith('COMBO')) openExit(line === 'COMBO KB' ? 'kb' : 'pad');
      else if (line.startsWith('BTN ') && exitOpen) sendExit('btn', line.slice(4));
      else if (line === 'AUDIO OK' || line === 'AUDIO NO') { const v = line === 'AUDIO OK' ? 'ok' : 'no'; if (cfg.audioCtl !== v) { cfg.audioCtl = v; saveCfg(); } }
      else if (line.startsWith('VOLSET')) log('volumen del juego: ' + line.slice(7) + '%');
      else if (line === 'GAMEWIN' && gameWinWaiter) gameWinWaiter();
    }
  });
  bridge.on('error', (e) => { log('puente: ' + e.message); bridge = null; });
  bridge.on('exit', () => { bridge = null; });
}
function stopBridge() { if (bridge) { bridgeCmd('QUIT'); const b = bridge; bridge = null; setTimeout(() => { try { b.kill(); } catch (e) {} }, 500); } }
function setGameVolume(v) {
  const t = Math.max(0, Math.min(100, parseInt(v, 10) || 0));
  if (game && cfg.audioCtl !== 'no') bridgeCmd('VOLUME ' + game.pid + ' ' + t);
}

function openExit(via) {
  if (!game || exitOpen || !alive(exitWin) || !alive(win)) return;
  exitOpen = true;
  exitWin.setBounds(screen.getPrimaryDisplay().bounds);
  exitWin.show(); exitWin.setAlwaysOnTop(true, 'screen-saver');
  bridgeCmd('FOCUS ' + hwnd(exitWin));      // el juego pierde el foco -> PPSSPP se pausa
  exitWin.focus();
  sendExit('show', { lang: cfg.ui || 'es', via: via || 'pad', gvol: cfg.gvol || '100' });
}
function closeExit(back) {
  exitOpen = false;
  if (!alive(win) || !alive(exitWin)) return;
  if (back) {
    win.setAlwaysOnTop(true, 'screen-saver');
    win.show(); if (cfg.launcherFull !== 'off') win.setFullScreen(true);
    bridgeCmd('FOCUS ' + hwnd(win)); win.focus();
    setTimeout(() => { exitWin.hide(); sendExit('hide'); }, 120);
    if (game) { const g = game; bridgeCmd('CLOSEPID ' + g.pid); setTimeout(() => { if (game === g) { try { g.kill(); } catch (e) {} } }, 5000); }
  } else {
    exitWin.hide(); sendExit('hide');
    if (game) bridgeCmd('FOCUSPID ' + game.pid);
  }
}

// PPSSPP: listo para lanzar / lanzar (Windows portable, Linux Flatpak o binario con su propia carpeta de datos)
function ppOk() { return paths.flatpak ? true : exists(paths.ppsspp); }
function spawnPpsspp(args, dirs) {
  if (paths.flatpak) {
    const perms = [...new Set(dirs.concat(paths.cache))].map((d) => '--filesystem=' + d);
    return spawn('flatpak', ['run', ...perms, paths.ppsspp.slice(8), ...args], { stdio: 'ignore' });
  }
  const env = IS_LINUX ? Object.assign({}, process.env, { XDG_CONFIG_HOME: paths.xdgHome }) : process.env;
  return spawn(paths.ppsspp, args, { cwd: path.dirname(paths.ppsspp), stdio: 'ignore', env });
}

// Espera a que la ventana de PPSSPP sea visible y la emulación esté en marcha (lo comprueba el puente: GAMEWIN)
let gameWinWaiter = null;
function waitGameWindow(pid) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (ok) => { if (!done) { done = true; gameWinWaiter = null; resolve(ok); } };
    gameWinWaiter = () => finish(true);
    if (!IS_WIN) { setTimeout(() => finish(true), 3000); return; }
    bridgeCmd('WAITWIN ' + pid);
    setTimeout(() => finish(false), 20000);
  });
}

// ---------------- jugar
async function play(version, iconSet) {
  if (game || busy) return;
  busy = true;
  try {
    if (!ppOk()) throw new Error(IS_LINUX ? 'No encuentro PPSSPP: instálalo (Flatpak org.ppsspp.PPSSPP o el paquete ppsspp de tu distribución)' : 'No encuentro PPSSPP: ' + paths.ppsspp);
    let iso;
    if (version === 'es') iso = await buildSpanish();
    else if (version === 'jp') iso = isoOf('jp');
    else iso = isoOf('us') || isoOf('eu');
    if (!iso) throw new Error(version === 'jp' ? 'No encuentro la ISO japonesa' : 'No encuentro tu ISO americana o europea');
    const gameId = iso.id;

    writeControls();
    await applyButtons(iconSet, gameId);
    const mods = applyMods(gameId, version);
    writeTexturesIni(gameId, mods.tex);
    const res = String(cfg.res || '1080');
    const ir = { 720: 3, 1080: 4, 1440: 6, 2160: 8 }[res] || 4;
    const mode = cfg.mode || 'full';
    const disp = screen.getPrimaryDisplay(), sf = disp.scaleFactor || 1;
    const scrW = Math.round(disp.size.width * sf), scrH = Math.round(disp.size.height * sf);
    // Ventana: 16:9 al ~80% de la pantalla (en píxeles reales). Sin bordes: toda la pantalla.
    let ww, wh;
    if (mode === 'border') { ww = scrW; wh = scrH; }
    else { const k = Math.min(scrW * 0.8 / 1600, scrH * 0.8 / 900); ww = Math.round(1600 * k); wh = Math.round(900 * k); }
    const gvol = Math.max(0, Math.min(100, parseInt(cfg.gvol || '100', 10)));
    const ini = path.join(paths.system, 'ppsspp.ini');
    const vk = (cfg.backend || 'vulkan') === 'vulkan', texUp = cfg.texUp || 'xbrz';
    setIni(ini, {
      General: { FirstRun: 'False', CheckForNewVersion: 'False', DiscordPresence: 'False', PauseOnLostFocus: 'True', PauseWhenMinimized: 'True',
        Language: cfg.ui === 'en' ? 'en_US' : 'es_ES', EnableCheats: mods.cheats ? 'True' : 'False', AskForExitConfirmationAfterSeconds: 0,
        IgnoreBadMemAccess: 'True', EnablePlugins: 'True',
        // sin avisos de PPSSPP encima del juego (NotificationPos = -1 = ninguna posición)
        NotificationPos: -1,
        // PPSSPP lee la posición y el tamaño de la ventana de [General] (no de [Graphics])
        // Depurador local de PPSSPP: solo mientras dure el rastreo de cámara (scripts\07 crea data\depurador.on)
        RemoteDebuggerOnStartup: exists(path.join(DATA, 'depurador.on')) ? 'True' : 'False',
        ...(exists(path.join(DATA, 'depurador.on')) ? { RemoteISOPort: 45690 } : {}),
        WindowX: mode === 'border' ? 0 : -1, WindowY: mode === 'border' ? 0 : -1, WindowWidth: ww, WindowHeight: wh, WindowSizeState: 0 },
      Graphics: { GraphicsBackend: { vulkan: '3 (VULKAN)', dx11: IS_WIN ? '2 (DIRECT3D11)' : '0 (OPENGL)', opengl: '0 (OPENGL)' }[cfg.backend || 'vulkan'],
        InternalResolution: ir, AnisotropyLevel: { 1: 0, 4: 2, 16: 4 }[cfg.af || '16'], MultiSampleLevel: { 1: 0, 2: 1, 4: 2, 8: 3 }[cfg.aa || '1'] || 0,
        VSync: (cfg.vsync || 'on') === 'on' ? 'True' : 'False', FrameSkip: 0, AutoFrameSkip: 'False', ReplaceTextures: 'True',
        SaveNewTextures: cfg.dumpTex === 'on' ? 'True' : 'False', FullScreen: mode === 'full' ? 'True' : 'False',
        ShowFPSCounter: cfg.fps === 'on' ? 3 : 0,
        // Mejora de texturas: en Vulkan por GPU (shader de cómputo, sin tirones); en DX11/OpenGL por CPU
        TexHardwareScaling: vk && texUp !== 'off' ? 'True' : 'False',
        TextureShader: vk ? ({ xbrz: 'Tex4xBRZ', mmpx: 'TexMMPXAdvanced', spline: 'TexSpline36_4x' }[texUp] || 'Off') : 'Off',
        TexScalingLevel: !vk && texUp !== 'off' ? 3 : 1, TexScalingType: texUp === 'spline' ? 2 : 0,
        TexDeposterize: texUp !== 'off' ? 'True' : 'False' },
      PostShaderList: { PostShader1: { sharpen: 'Sharpen', fxaa: 'FXAA', natural: 'NaturalA' }[cfg.post] || 'Off' },
      Achievements: { AchievementsEnable: 'False' },
      Sound: { GlobalVolume: Math.round(gvol / 10), GameVolume: cfg.audioCtl === 'no' ? gvol : 100 },
      SystemParam: { ButtonPreference: 1, Language: version === 'jp' ? 0 : 1 },
      Control: { UseMouse: cfg.kbCam !== 'keys' ? 'True' : 'False', MouseSensitivity: (0.02 + 0.18 * (parseInt(cfg.sens || 50, 10) / 100)).toFixed(3) }
    });
    for (const f of mods.ini) { try { setIni(ini, parseIni(f)); } catch (e) { log('ajustes de mod: ' + e.message); } }

    const args = [mode === 'full' ? '--fullscreen' : '--windowed', iso.file];
    log('Iniciando (' + mode + ' ' + ww + 'x' + wh + '): ' + paths.ppsspp + ' ' + args.join(' '));
    // En pantalla completa el launcher tapa el arranque; en ventana/sin bordes NO debe quedar encima del juego
    if (mode === 'full') win.setAlwaysOnTop(true, 'screen-saver'); else win.setAlwaysOnTop(false);
    game = spawnPpsspp(args, [path.dirname(iso.file)]);
    gameStart = Date.now();
    startBridge();
    bridgeCmd('GAMEPID ' + game.pid);
    bridgeCmd('SKIN ' + game.pid);   // icono y título del juego en la ventana de PPSSPP
    if (freecamOn()) {
      const kb = Object.assign({}, KB_DEF, cfg.kbBinds || {});
      bridgeCmd(['FREECAM', game.pid, cfg.kbCam !== 'keys' ? 1 : 0, parseInt(cfg.sens || 50, 10) || 50, cfg.camInvX === 'on' ? 1 : 0,
        cfg.invert === 'on' ? 1 : 0, cfg.padInvert === 'on' ? 1 : 0, vkOf(kb.rs_up), vkOf(kb.rs_down), vkOf(kb.rs_left), vkOf(kb.rs_right),
        vkOf(kb.du), vkOf(kb.dd), vkOf(kb.dl), vkOf(kb.dr), vkOf(kb.l)].join(' '));
      log('Cámara libre activada');
    }
    setGameVolume(gvol);
    const myGame = game;
    waitGameWindow(game.pid).then((ok) => {
      if (game !== myGame) return;
      log(ok ? 'Ventana del juego lista' : 'La ventana del juego tardó demasiado; se muestra igualmente');
      if (mode === 'border') {
        bridgeCmd('BORDERLESS ' + myGame.pid + ' ' + ww + ' ' + wh);
        setTimeout(() => { if (game === myGame) bridgeCmd('BORDERLESS ' + myGame.pid + ' ' + ww + ' ' + wh); }, 1500);
      }
      // primero se trae el juego al frente y después se oculta el launcher (si no, en ventana quedaba detrás)
      bridgeCmd('FOCUSPID ' + myGame.pid);
      setTimeout(() => {
        if (game !== myGame || !alive(win)) return;
        win.setAlwaysOnTop(false); if (win.isFullScreen()) win.setFullScreen(false); win.hide();
        bridgeCmd('FOCUSPID ' + myGame.pid);
        setTimeout(() => { if (game === myGame) bridgeCmd('FOCUSPID ' + myGame.pid); }, 1200);
      }, 500);
    });
    game.on('error', (e) => { log('Error al iniciar PPSSPP: ' + e.message); game = null; stopBridge(); if (alive(win)) { win.setAlwaysOnTop(false); win.show(); } send('error', e.message); });
    game.on('exit', (code) => {
      const secs = Math.round((Date.now() - gameStart) / 1000);
      log('PPSSPP cerrado (código ' + code + ', ' + secs + ' s)');
      if (secs > 20) {
        cfg.playtime = (parseInt(cfg.playtime || 0, 10) || 0) + secs;
        cfg.lastPlayed = Date.now(); cfg.lastVersion = version; cfg.sessions = (parseInt(cfg.sessions || 0, 10) || 0) + 1;
        saveCfg();
      }
      game = null;
      stopBridge();
      if (exitOpen) { exitOpen = false; if (alive(exitWin)) exitWin.hide(); sendExit('hide'); }
      if (!alive(win)) return;
      win.show(); if (cfg.launcherFull !== 'off') win.setFullScreen(true); win.focus();
      setTimeout(() => { if (alive(win)) win.setAlwaysOnTop(false); }, 400);
      send('gameClosed', { playtime: cfg.playtime || 0 });
      send('state', state());
    });
    send('gameStarted', version);
  } finally { busy = false; }
}

function toggleFull(force) {
  if (!alive(win)) return;
  const on = typeof force === 'boolean' ? force : !win.isFullScreen();
  win.setFullScreen(on); cfg.launcherFull = on ? 'on' : 'off'; saveCfg();
}
const keep = () => ({ launcherFull: cfg.launcherFull, audioCtl: cfg.audioCtl, playtime: cfg.playtime, mods: cfg.mods,
  lastPlayed: cfg.lastPlayed, lastVersion: cfg.lastVersion, sessions: cfg.sessions });
const fail = (e) => { log('ERROR: ' + (e && e.stack || e)); send('error', e && e.message || String(e)); };

ipcMain.on('msg', (_e, raw) => {
  let m; try { m = JSON.parse(raw); } catch (e) { return; }
  try {
    switch (m.cmd) {
      case 'init': log('Interfaz lista en ' + Math.round(process.uptime() * 1000) + ' ms'); send('state', state()); scanIsos().then(() => send('state', state())).catch(fail); break;
      case 'rescan': hashCache = readJson(HASHES, {}); scanIsos().then(() => send('state', state())).catch(fail); break;
      case 'save': if (m.config) { cfg = Object.assign({}, m.config, keep()); saveCfg(); } break;
      case 'play': if (m.config) { cfg = Object.assign({}, m.config, keep()); saveCfg(); } play(m.version, m.iconSet).catch(fail); break;
      case 'prepareEs': buildSpanish().then(() => send('state', state())).catch(fail); break;
      case 'mod': cfg.mods = Object.assign({}, cfg.mods || {}, { [m.id]: !!m.on }); saveCfg(); send('state', state()); break;
      case 'openFolder': { const t = { mods: paths.mods, juego: paths.isoDirs[0], capturas: paths.shots, partidas: paths.saves }[m.which];
        if (t) { fs.mkdirSync(t, { recursive: true }); shell.openPath(t); } break; }
      case 'minimize': if (alive(win)) win.minimize(); break;
      case 'toggleFull': toggleFull(); break;
      case 'close': app.quit(); break;
      case 'exitYes': closeExit(true); break;
      case 'exitNo': closeExit(false); break;
      case 'gvol': cfg.gvol = String(Math.max(0, Math.min(100, parseInt(m.value, 10) || 0))); saveCfg(); setGameVolume(cfg.gvol); send('cfgPatch', { gvol: cfg.gvol }); break;
      case 'achTest': showAchievement({ title: m.title || 'Episodio 1', description: m.description || 'Has completado el episodio.', mark: m.mark || '1' }); break;
      case 'toastDone': toastBusy = false; if (toastQueue.length) nextToast(); else if (toastWin && !toastWin.isDestroyed()) toastWin.hide(); break;
      case 'device': if (m.value === 'kb' || m.value === 'pad') { cfg.lastDevice = m.value; saveCfg(); } break;
    }
  } catch (e) { fail(e); }
});

function createWindow() {
  const wa = screen.getPrimaryDisplay().workAreaSize;
  const fit = Math.min(1, (wa.width * 0.9) / 1280, (wa.height * 0.9) / 720);
  if (process.argv.includes('--windowed')) { cfg.launcherFull = 'off'; saveCfg(); }
  win = new BrowserWindow({
    width: Math.round(1280 * fit), height: Math.round(720 * fit), center: true,
    frame: false, resizable: true, maximizable: false, fullscreenable: true, minWidth: 640, minHeight: 360,
    backgroundColor: '#0b0b0d', show: false, title: APP_NAME,
    icon: path.join(UI, 'assets', 'icon.ico'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true }
  });
  win.setMenu(null);
  win.loadURL('pt://ui/index.html');
  win.setAspectRatio(16 / 9);
  win.once('ready-to-show', () => { win.show(); if (cfg.launcherFull !== 'off') win.setFullScreen(true); });
  win.on('enter-full-screen', () => send('fullscreen', true));
  win.on('leave-full-screen', () => send('fullscreen', false));
  win.webContents.on('before-input-event', (e, input) => {
    if (input.type !== 'keyDown') return;
    if (input.key === 'F11' || (input.alt && input.key === 'Enter')) { e.preventDefault(); toggleFull(); }
  });
}

if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', () => { if (win) { win.show(); win.focus(); } });
  app.whenReady().then(async () => {
    fs.mkdirSync(DATA, { recursive: true });
    // la caché de Chromium solo se limpia si cambiaron los archivos de la interfaz (limpiarla siempre retrasaba el arranque)
    try {
      const sig = ['index.html', 'exit.html', 'toast.html', 'botones.html'].map((f) => { try { return fs.statSync(path.join(UI, f)).mtimeMs; } catch (e) { return 0; } }).join(',');
      const sf = path.join(DATA, 'ui_firma.txt');
      if ((exists(sf) ? fs.readFileSync(sf, 'utf8') : '') !== sig) { await session.defaultSession.clearCache(); fs.writeFileSync(sf, sig); log('Caché de la interfaz renovada'); }
    } catch (e) {}
    protocol.handle('pt', (req) => {
      const u = new URL(req.url);
      const rel = decodeURIComponent(u.pathname).replace(/^\/+/, '');
      const base = u.host === 'shots' ? path.resolve(paths.shots) : path.resolve(UI);
      const file = path.resolve(base, rel);
      if (!file.startsWith(base + path.sep)) return new Response('Prohibido', { status: 403 });
      if (u.host === 'shots' && !/\.(png|jpe?g)$/i.test(file)) return new Response('Prohibido', { status: 403 });
      return net.fetch(pathToFileURL(file).toString());
    });
    createWindow();
    // las ventanas de pausa y avisos se crean después, para no competir con la carga del menú
    setTimeout(() => { if (!alive(exitWin)) createExitWindow(); if (!alive(toastWin)) createToastWindow(); }, 2500);
    log('Launcher iniciado. PPSSPP: ' + paths.ppsspp);
  });
  app.on('before-quit', () => stopBridge());
  app.on('window-all-closed', () => app.quit());
}
