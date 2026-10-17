// Instalador de The 3rd Birthday — Dionixu's Launcher (Windows y Linux)
// No incluye el juego: usa la copia original del usuario (versión americana ULUS-10567 y/o japonesa ULJM-05798),
// la verifica por MD5 (Redump) y, si es la americana, genera la versión en español (UNDUB) con el parche integrado.
'use strict';
const { app, BrowserWindow, ipcMain, dialog, protocol, net, shell } = require('electron');
const { pathToFileURL } = require('url');
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const { spawn } = require('child_process');

const IS_WIN = process.platform === 'win32';
const IS_LINUX = process.platform === 'linux';
const ROOT = path.dirname(process.execPath);            // Windows: carpeta del instalador · Linux: $APPDIR (AppImage)
const UI = path.join(__dirname, 'ui');
const DIRNAME = 'The 3rd Birthday';
const EXE_NAME = IS_WIN ? 'The3rdBirthday.exe' : 'the3rdbirthday';
const FLATPAK_ID = 'org.ppsspp.PPSSPP';
// Volcados Redump admitidos
const KNOWN = {
  '47A7CB8E9E73D8AABEF8139DB7EE522B': { kind: 'us', id: 'ULUS10567', file: 'The 3rd Birthday (USA).iso' },
  '688CC34138A19441044BCE3D3A4C429B': { kind: 'jp', id: 'ULJM05798', file: 'The 3rd Birthday (Japan).iso' }
};
const ES_MD5 = 'C0E56A15C0D92450BDB1BE09426B7300';   // resultado del parche (español UNDUB)
const ISO_BYTES = 1.47e9;
const PAYLOADS = [path.join(ROOT, 'payload'), path.resolve(ROOT, '..', 'payload'),
  ...(process.env.APPIMAGE ? [path.join(path.dirname(process.env.APPIMAGE), 'payload')] : [])].filter((p, i, a) => a.indexOf(p) === i);
const payload = (...rel) => {
  for (const p of PAYLOADS) { const f = path.join(p, ...rel); if (fs.existsSync(f)) return f; }
  return path.join(PAYLOADS[0], ...rel);
};

if (IS_LINUX) app.commandLine.appendSwitch('ozone-platform-hint', 'auto');
protocol.registerSchemesAsPrivileged([{ scheme: 'tbi', privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true } }]);
app.setPath('userData', path.join(os.tmpdir(), 't3b-installer'));
app.setName("Dionixu's Launcher");

let win = null, installing = false;
const send = (type, data) => { if (win && !win.isDestroyed()) win.webContents.send('msg', JSON.stringify({ type, data })); };
const exists = (f) => { try { return fs.existsSync(f); } catch (e) { return false; } };
const logLines = [];
const log = (s) => { logLines.push(new Date().toISOString() + '  ' + s); send('log', s); };

// ---------------------------------------------------------------- utilidades
const md5 = (file, onPct) => new Promise((ok, ko) => {
  const size = fs.statSync(file).size; let done = 0, last = -1;
  const h = crypto.createHash('md5'); const s = fs.createReadStream(file, { highWaterMark: 4 << 20 });
  s.on('data', (d) => { h.update(d); done += d.length; const p = Math.floor(done * 100 / size); if (onPct && p !== last) { last = p; onPct(p); } });
  s.on('end', () => ok(h.digest('hex').toUpperCase())); s.on('error', ko);
});
const copyBig = (src, dst, onPct) => new Promise((ok, ko) => {
  const size = fs.statSync(src).size; let done = 0;
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  const r = fs.createReadStream(src, { highWaterMark: 8 << 20 }), w = fs.createWriteStream(dst);
  r.on('data', (d) => { done += d.length; if (onPct) onPct(done / size); });
  r.on('error', ko); w.on('error', ko); w.on('finish', ok);
  r.pipe(w);
});
function copyDir(src, dst, filter) {
  fs.mkdirSync(dst, { recursive: true });
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name), d = path.join(dst, e.name);
    if (filter && !filter(s, e)) continue;
    if (e.isDirectory()) copyDir(s, d, filter);
    else if (e.isSymbolicLink()) { try { fs.symlinkSync(fs.readlinkSync(s), d); } catch (x) {} }
    else fs.copyFileSync(s, d);
  }
}
function freeBytes(dir) {
  let d = path.resolve(dir);
  while (!exists(d)) { const up = path.dirname(d); if (up === d) break; d = up; }
  try { const s = fs.statfsSync(d); return s.bavail * s.bsize; } catch (e) { return Infinity; }
}
const which = (cmd) => (process.env.PATH || '').split(IS_WIN ? ';' : ':').map((d) => path.join(d, cmd)).find((p) => exists(p)) || null;
const run = (cmd, args, opts = {}) => new Promise((ok) => {
  const p = spawn(cmd, args, Object.assign({ windowsHide: true }, opts));
  let out = '', err = '';
  if (p.stdout) p.stdout.on('data', (d) => { out += d; });
  if (p.stderr) p.stderr.on('data', (d) => { err += d; });
  p.on('error', (e) => ok({ code: -1, out, err: err + e.message }));
  p.on('exit', (code) => ok({ code, out, err }));
});

// ---------------------------------------------------------------- PPSSPP en Linux (el del usuario)
function linuxDetect() {
  const found = [];
  for (const b of ['/var/lib/flatpak/app/' + FLATPAK_ID, path.join(os.homedir(), '.local/share/flatpak/app', FLATPAK_ID)])
    if (exists(b)) { found.push({ kind: 'flatpak', path: 'flatpak:' + FLATPAK_ID }); break; }
  for (const c of ['PPSSPPSDL', 'ppsspp', 'PPSSPPQt', 'ppsspp-sdl']) { const b = which(c); if (b) { found.push({ kind: 'bin', path: b }); break; } }
  return found;
}

// ---------------------------------------------------------------- instalación
async function install(o) {
  const L = o.lang === 'en' ? 'en' : 'es';
  const dir = path.resolve(o.dir);
  const step = (key, pct) => { send('prog', { key, pct }); };
  const isos = [o.us, o.jp].filter(Boolean);
  log('Instalador ' + app.getVersion() + ' · ' + process.platform + ' · destino: ' + dir);
  if (!isos.length) throw new Error('noiso');
  if (!exists(payload('launcher', 'app', 'main.js'))) throw new Error('payload');
  // 0. espacio: launcher ~0.5 GB + ISOs copiadas + español (1.4 GB)
  const need = 0.6e9 + (o.copy ? isos.length * ISO_BYTES : 0) + (o.us && o.spanish ? 1.4e9 : 0);
  const free = freeBytes(dir);
  log('espacio libre: ' + (free / 1e9).toFixed(1) + ' GB, necesario ~' + (need / 1e9).toFixed(1) + ' GB');
  if (free < need) throw new Error('space:' + Math.ceil(need / 1e9));
  fs.mkdirSync(dir, { recursive: true });

  // 1. verificar las copias (MD5 Redump)
  step('check', 2);
  const found = {};
  for (const f of isos) {
    const h = await md5(f, (p) => step('check', 2 + p * 0.1));
    const k = KNOWN[h];
    log('ISO ' + path.basename(f) + ' -> ' + h + (k ? ' (' + k.id + ')' : ' (desconocida)'));
    if (!k) throw new Error('verify:' + path.basename(f));
    found[k.kind] = { file: f, md5: h, k };
  }

  // 2. launcher (el ejecutable es el mismo Electron del instalador, con el icono del juego)
  step('launcher', 14);
  const LD = path.join(dir, 'launcher');
  const keep = path.join(LD, 'data');
  const keepTmp = path.join(dir, '.data_anterior');
  if (exists(keep)) { fs.rmSync(keepTmp, { recursive: true, force: true }); fs.renameSync(keep, keepTmp); log('se conservan tus ajustes anteriores'); }
  fs.rmSync(LD, { recursive: true, force: true });
  copyDir(ROOT, LD, (s, e) => {
    const rel = path.relative(ROOT, s);
    return !(rel === 'resources' && e.isDirectory()) && rel !== 'payload' && !/\.txt$/i.test(rel) && !/^instalar/i.test(rel)
      && rel !== 'AppRun' && !/\.desktop$/i.test(rel) && !/^\.DirIcon$/.test(rel) && !/^usr$/.test(rel) && !/^the3rdbirthday\.png$/i.test(rel);
  });
  if (IS_WIN) fs.copyFileSync(process.execPath, path.join(LD, EXE_NAME));
  else {
    const exeSrc = exists(path.join(LD, 'electron')) ? 'electron' : path.basename(process.execPath);
    if (exeSrc !== EXE_NAME) fs.renameSync(path.join(LD, exeSrc), path.join(LD, EXE_NAME));
  }
  copyDir(payload('launcher', 'app'), path.join(LD, 'resources', 'app'), (s) => IS_WIN || !/\.ps1$/i.test(s));
  copyDir(payload('launcher', 'ui'), path.join(LD, 'ui'));
  fs.mkdirSync(path.join(LD, 'data'), { recursive: true });
  if (exists(keepTmp)) { copyDir(keepTmp, path.join(LD, 'data')); fs.rmSync(keepTmp, { recursive: true, force: true }); }
  if (!IS_WIN) for (const f of [EXE_NAME, 'chrome_crashpad_handler', 'chrome-sandbox']) try { fs.chmodSync(path.join(LD, f), 0o755); } catch (e) {}

  // 3. PPSSPP (Windows: portable incluido) y herramientas
  step('engine', 24);
  if (IS_WIN) {
    copyDir(payload('PPSSPP'), path.join(dir, 'PPSSPP'), (s) => !/[\\/]memstick[\\/]PSP[\\/](SAVEDATA|PPSSPP_STATE)/i.test(s));
    fs.mkdirSync(path.join(dir, 'PPSSPP', 'memstick', 'PSP', 'SYSTEM'), { recursive: true });
  }
  copyDir(payload('herramientas'), path.join(dir, 'herramientas'));
  if (!IS_WIN) try { fs.chmodSync(path.join(dir, 'herramientas', 'xdelta3'), 0o755); } catch (e) {}
  copyDir(payload('parche'), path.join(dir, 'parche'));
  for (const d of ['juego', 'cache', 'mods']) fs.mkdirSync(path.join(dir, d), { recursive: true });

  // 4. tus ISOs: se copian a juego\ (recomendado) o se usan desde donde están
  const isoFiles = [], hashes = {};
  let pc = 30;
  for (const kind of ['us', 'jp']) {
    const f = found[kind]; if (!f) continue;
    let target = f.file;
    if (o.copy) {
      target = path.join(dir, 'juego', f.k.file);
      if (path.resolve(target) !== path.resolve(f.file)) {
        step('copy', pc);
        const base = pc;
        await copyBig(f.file, target, (r) => step('copy', base + r * 18));
        log('copiada: ' + target);
      }
      pc += 18;
    } else isoFiles.push(f.file);
    const st = fs.statSync(target);
    hashes[target.toLowerCase()] = { size: st.size, mtime: st.mtimeMs, md5: f.md5.toLowerCase() };
  }

  // 5. versión en español (UNDUB) desde la americana
  if (found.us && o.spanish) {
    step('spanish', 68);
    const xd = path.join(dir, 'herramientas', IS_WIN ? 'xdelta3.exe' : 'xdelta3');
    const tool = exists(xd) ? xd : (IS_WIN ? null : which('xdelta3'));
    const patch = path.join(dir, 'parche', 'T3B_ES_desde_ULUS10567.xdelta');
    const out = path.join(dir, 'cache', 'T3B_ES.iso'), tmp = out + '.tmp';
    if (!tool || !exists(patch)) log('español: falta xdelta3 o el parche; el launcher lo creará al jugar');
    else {
      const realSrc = o.copy ? path.join(dir, 'juego', found.us.k.file) : found.us.file;
      const t = setInterval(() => { try { step('spanish', 68 + Math.min(1, fs.statSync(tmp).size / 1.3877e9) * 22); } catch (e) {} }, 1000);
      const r = await run(tool, ['-d', '-f', '-B', '1073741824', '-s', realSrc, patch, tmp]);
      clearInterval(t);
      if (r.code !== 0) { try { fs.rmSync(tmp, { force: true }); } catch (e) {} throw new Error('patch:' + (r.err || r.code)); }
      const h = await md5(tmp);
      if (h !== ES_MD5) { fs.rmSync(tmp, { force: true }); throw new Error('patch:md5'); }
      fs.renameSync(tmp, out);
      const st = fs.statSync(out);
      hashes[out.toLowerCase()] = { size: st.size, mtime: st.mtimeMs, md5: ES_MD5.toLowerCase() };
      log('español (UNDUB) listo: ' + out);
    }
  }

  // 6. configuración inicial del launcher
  step('config', 91);
  const cfgFile = path.join(LD, 'data', 'config.json');
  let cfg = {}; try { cfg = JSON.parse(fs.readFileSync(cfgFile, 'utf8')); } catch (e) {}
  cfg.ui = L;
  if (!cfg.version) cfg.version = found.us ? (L === 'es' ? 'es' : 'en') : 'jp';
  if (cfg.launcherFull == null) cfg.launcherFull = 'off';
  if (IS_LINUX && (!cfg.backend || cfg.backend === 'dx11')) cfg.backend = 'vulkan';
  fs.writeFileSync(cfgFile, JSON.stringify(cfg, null, 1));
  const pj = { isoDirs: ['../juego'], isoFiles: isoFiles.map((f) => path.relative(LD, f)) };
  if (IS_LINUX && o.ppsspp) pj.ppsspp = o.ppsspp;
  fs.writeFileSync(path.join(LD, 'data', 'paths.json'), JSON.stringify(pj, null, 1));
  fs.writeFileSync(path.join(LD, 'data', 'isos.json'), JSON.stringify(hashes, null, 1));

  // 7. Steam: script para agregar el juego (con su arte)
  if (exists(payload('steam'))) {
    copyDir(path.join(payload('steam'), 'arte'), path.join(dir, 'steam', 'arte'));
    const files = IS_WIN ? ['AGREGAR_A_STEAM.bat', 'AGREGAR_A_STEAM.ps1'] : ['agregar_a_steam.sh', 'agregar_a_steam.py'];
    for (const f of files.concat('LEEME - README.txt')) if (exists(path.join(payload('steam'), f))) fs.copyFileSync(path.join(payload('steam'), f), path.join(dir, f));
    if (!IS_WIN) for (const f of files) try { fs.chmodSync(path.join(dir, f), 0o755); } catch (e) {}
  }

  // 8. accesos directos
  step('shortcuts', 95);
  const exe = path.join(LD, EXE_NAME);
  if (IS_WIN) {
    const q = (s) => s.replace(/'/g, "''");
    const lnk = (where) => `$s=(New-Object -ComObject WScript.Shell).CreateShortcut('${q(where)}');` +
      `$s.TargetPath='${q(exe)}';$s.WorkingDirectory='${q(LD)}';` +
      `$s.IconLocation='${q(path.join(LD, 'ui', 'assets', 'icon.ico'))}';$s.Description="The 3rd Birthday - Dionixu's Launcher";$s.Save()`;
    const targets = [path.join(dir, 'The 3rd Birthday.lnk')];
    if (o.desktop) targets.push(path.join(app.getPath('desktop'), 'The 3rd Birthday.lnk'));
    if (o.menu) targets.push(path.join(app.getPath('appData'), 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'The 3rd Birthday.lnk'));
    await run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', targets.map(lnk).join(';')]);
  } else {
    const desk = ['[Desktop Entry]', 'Type=Application', 'Name=The 3rd Birthday', "Comment=Dionixu's Launcher", 'Categories=Game;',
      `Exec="${exe}" --no-sandbox`, `Path=${LD}`, `Icon=${path.join(LD, 'ui', 'assets', 'icon.png')}`, 'Terminal=false', 'StartupWMClass=the3rdbirthday', ''].join('\n');
    const write = (f) => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, desk); try { fs.chmodSync(f, 0o755); } catch (e) {} };
    write(path.join(dir, 'The 3rd Birthday.desktop'));
    if (o.menu) write(path.join(os.homedir(), '.local', 'share', 'applications', 'the3rdbirthday.desktop'));
    if (o.desktop) {
      const r2 = await run('xdg-user-dir', ['DESKTOP']);
      const d = (r2.code === 0 && r2.out.trim()) || path.join(os.homedir(), 'Desktop');
      if (exists(d)) { const f = path.join(d, 'the3rdbirthday.desktop'); write(f); await run('gio', ['set', f, 'metadata::trusted', 'true']); }
    }
  }
  fs.writeFileSync(path.join(dir, 'instalacion.log'), logLines.join('\n') + '\n');
  step('done', 100);
  return { exe, dir: LD };
}

// si algo falla se borra lo que se generó (ISOs copiadas, español); nunca se toca nada fuera de la carpeta elegida
async function installSafe(o) {
  try { return await install(o); }
  catch (e) {
    const dir = path.resolve(o.dir);
    for (const f of [path.join(dir, 'cache', 'T3B_ES.iso.tmp')]) try { fs.rmSync(f, { force: true }); } catch (x) {}
    try { fs.writeFileSync(path.join(dir, 'instalacion.log'), logLines.join('\n') + '\nERROR: ' + e.message + '\n'); } catch (x) {}
    throw e;
  }
}

// ---------------------------------------------------------------- IPC
let lastInstall = null;
ipcMain.on('msg', async (_e, raw) => {
  let m; try { m = JSON.parse(raw); } catch (e) { return; }
  try {
    switch (m.cmd) {
      case 'init':
        send('state', {
          platform: process.platform, payloadOk: exists(payload('launcher', 'app', 'main.js')),
          defaultDir: IS_WIN ? path.join(app.getPath('documents'), DIRNAME) : path.join(os.homedir(), 'Games', DIRNAME),
          ppssppFound: IS_LINUX ? linuxDetect() : []
        });
        break;
      case 'pick': {
        const opts = m.kind === 'dir'
          ? { properties: ['openDirectory', 'createDirectory'], defaultPath: m.current || undefined }
          : m.kind === 'ppsspp'
            ? { properties: ['openFile', 'showHiddenFiles'] }
            : { properties: ['openFile'], filters: [{ name: 'PSP ISO', extensions: ['iso'] }, { name: '*', extensions: ['*'] }] };
        const r = await dialog.showOpenDialog(win, opts);
        if (r.canceled || !r.filePaths[0]) return;
        send('picked', { kind: m.kind, path: r.filePaths[0] });
        break;
      }
      case 'check': {   // MD5 de la ISO elegida (us / jp)
        const h = await md5(m.path, (p) => send('checking', { kind: m.kind, pct: p }));
        const k = KNOWN[h];
        send('checked', { kind: m.kind, path: m.path, md5: h, found: k ? k.kind : null, id: k ? k.id : null });
        break;
      }
      case 'install':
        if (installing) return;
        installing = true;
        try { lastInstall = await installSafe(m.opts); send('done', lastInstall); }
        catch (e) { log('ERROR: ' + (e.stack || e.message)); send('fail', { error: e.message }); }
        installing = false;
        break;
      case 'launch':
        if (lastInstall) {
          const p = spawn(lastInstall.exe, ['--windowed', ...(IS_LINUX ? ['--no-sandbox'] : [])], { cwd: lastInstall.dir, detached: true, stdio: 'ignore' });
          p.unref();
        }
        setTimeout(() => app.quit(), 600);
        break;
      case 'openFolder': if (lastInstall) shell.openPath(path.dirname(lastInstall.dir)); break;
      case 'minimize': win.minimize(); break;
      case 'close': if (!installing) app.quit(); break;
    }
  } catch (e) { send('fail', { error: e.message }); }
});

app.whenReady().then(() => {
  protocol.handle('tbi', (req) => {
    const rel = decodeURIComponent(new URL(req.url).pathname).replace(/^\/+/, '');
    const file = path.resolve(UI, rel);
    if (!file.startsWith(path.resolve(UI))) return new Response('', { status: 403 });
    if (!fs.existsSync(file)) return new Response('', { status: 404 });
    return net.fetch(pathToFileURL(file).toString()).catch(() => new Response('', { status: 404 }));
  });
  win = new BrowserWindow({
    width: 1040, height: 640, minWidth: 900, minHeight: 560, frame: false, resizable: false, backgroundColor: '#0b0b0d', show: false,
    title: "Dionixu's Launcher — The 3rd Birthday", icon: path.join(UI, 'assets', IS_WIN ? 'icon.ico' : 'icon.png'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true }
  });
  win.setMenu(null);
  win.loadURL('tbi://ui/index.html');
  win.once('ready-to-show', () => win.show());
  win.on('close', (e) => { if (installing) e.preventDefault(); });
});
app.on('window-all-closed', () => app.quit());
