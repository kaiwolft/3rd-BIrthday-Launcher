/*
 * t3b_logros - motor de logros sin conexion para The 3rd Birthday (PPSSPP)
 * Dionixu's Launcher
 *
 * Usa rcheevos (la misma libreria que RetroAchievements/PPSSPP) para evaluar las
 * condiciones oficiales del set del juego 3511 leyendo la memoria emulada de
 * PPSSPP desde fuera del proceso. No necesita internet y funciona tambien con la
 * version en espanol (UNDUB), que el servidor no acepta por su huella.
 *
 * Memoria (rcheevos, consola PSP): direccion RA 0x00000000-0x01FFFFFF = PSP 0x08000000-0x09FFFFFF.
 *   Windows: la base de la memoria de PPSSPP se pide a su ventana con WM_APP+0x3118 (la API para
 *            herramientas externas) y se lee con ReadProcessMemory en base + 0x08000000.
 *   Linux:   PPSSPP guarda la RAM emulada en un archivo compartido (/dev/shm/ppsspp_N.ram, ya
 *            desenlazado); se reabre via /proc/<pid>/fd (mismo usuario, sin ptrace). La RAM empieza
 *            despues del scratchpad (0x4000) y la VRAM (0x200000): offset 0x204000 (0x214000 con pagina nula).
 *
 * Uso:  t3b_logros <pid_ppsspp> <logros.txt>
 *   logros.txt : una linea por logro ->  id<TAB>memaddr   (puede estar vacio)
 * Salida (stdout): READY n · HOOKED · UNLOCK id · PROGRESS id v t · LOST
 * Entrada (stdin): QUIT
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "rc_runtime.h"

static int plat_open(unsigned long pid);
static int plat_find_ram(void);
static int plat_read(uint32_t off, uint8_t *dst, uint32_t size);
static int plat_alive(void);
static int plat_in_game(void);
static double plat_now_ms(void);
static void plat_sleep_ms(double ms);
static void plat_start_stdin(void);
static void plat_describe(void);
static volatile int quit_req;

#define RAM_SIZE 0x02000000u   /* 32 MB visibles para RA */
#define PAGE 0x1000u
#define NPAGES (RAM_SIZE / PAGE)

static uint8_t *cache;
static uint32_t *stamp;
static uint32_t frame_no = 1;

static uint8_t *page_ptr(uint32_t off)
{
  uint32_t pg = off / PAGE;
  if (stamp[pg] != frame_no) {
    if (!plat_read(pg * PAGE, cache + (size_t)pg * PAGE, PAGE))
      memset(cache + (size_t)pg * PAGE, 0, PAGE);
    stamp[pg] = frame_no;
  }
  return cache + (size_t)pg * PAGE + (off % PAGE);
}

/* rcheevos v11: devuelve el valor (little endian, como la PSP) de 1, 2 o 4 bytes */
static uint32_t RC_CCONV peek(uint32_t address, uint32_t num_bytes, void *ud)
{
  uint32_t i, v = 0;
  (void)ud;
  if (address + num_bytes > RAM_SIZE || num_bytes > 4) return 0;
  for (i = 0; i < num_bytes; i++) v |= (uint32_t)*page_ptr(address + i) << (8 * i);
  return v;
}

static rc_runtime_t runtime;

static void out(const char *fmt, uint32_t a, uint32_t b, uint32_t c)
{
  printf(fmt, a, b, c);
  fflush(stdout);
}

static void RC_CCONV on_event(const rc_runtime_event_t *e)
{
  if (e->type == RC_RUNTIME_EVENT_ACHIEVEMENT_TRIGGERED) {
    out("UNLOCK %u\n", e->id, 0, 0);
    rc_runtime_deactivate_achievement(&runtime, e->id);
  } else if (e->type == RC_RUNTIME_EVENT_ACHIEVEMENT_PROGRESS_UPDATED) {
    unsigned v = 0, t = 0;
    if (rc_runtime_get_achievement_measured(&runtime, e->id, &v, &t) && t)
      out("PROGRESS %u %u %u\n", e->id, v, t);
  }
}

static int load_defs(const char *path)
{
  FILE *f = fopen(path, "rb");
  size_t cap = 1 << 16, len;
  char *line;
  int n = 0;
  if (!f) return -1;
  line = (char *)malloc(cap);
  while (fgets(line, (int)cap, f)) {
    char *tab;
    uint32_t id;
    len = strlen(line);
    while (len == cap - 1 && line[len - 1] != '\n') {
      cap *= 2;
      line = (char *)realloc(line, cap);
      if (!fgets(line + len, (int)(cap - len), f)) break;
      len = strlen(line);
    }
    while (len && (line[len - 1] == '\n' || line[len - 1] == '\r')) line[--len] = 0;
    tab = strchr(line, '\t');
    if (!tab) continue;
    *tab = 0;
    id = (uint32_t)strtoul(line, NULL, 10);
    if (rc_runtime_activate_achievement(&runtime, id, tab + 1, NULL, 0) == RC_OK) n++;
    else fprintf(stderr, "logro %u invalido\n", id);
  }
  free(line);
  fclose(f);
  return n;
}

#ifndef T3B_TEST
int main(int argc, char **argv)
{
  int n;
  double t0, next;
  if (argc < 3) { fprintf(stderr, "uso: t3b_logros <pid> <logros.txt>\n"); return 2; }
  rc_runtime_init(&runtime);
  n = load_defs(argv[2]);
  if (n < 0) { fprintf(stderr, "no puedo abrir %s\n", argv[2]); return 3; }
  out("READY %u\n", (uint32_t)n, 0, 0);

  cache = (uint8_t *)malloc(RAM_SIZE);
  stamp = (uint32_t *)calloc(NPAGES, 4);
  plat_start_stdin();
  if (!plat_open(strtoul(argv[1], NULL, 10))) { fprintf(stderr, "no puedo abrir el proceso %s\n", argv[1]); return 4; }

  /* esperar a que PPSSPP tenga el juego cargado */
  while (!plat_find_ram()) {
    if (quit_req || !plat_alive()) { out("LOST\n", 0, 0, 0); return 0; }
    plat_sleep_ms(500);
  }
  out("HOOKED\n", 0, 0, 0);
  plat_describe();

  /* bucle a 60 Hz */
  t0 = plat_now_ms();
  next = 0;
  while (!quit_req) {
    double ms;
    if ((frame_no & 31) == 0 && !plat_alive()) { out("LOST\n", 0, 0, 0); break; }
    if (plat_in_game()) rc_runtime_do_frame(&runtime, on_event, peek, NULL, NULL);
    frame_no++;
    next += 1000.0 / 60.0;
    ms = plat_now_ms() - t0;
    if (next > ms) plat_sleep_ms(next - ms);
    else if (ms - next > 250) next = ms;
  }
  return 0;
}
#endif

#if defined(T3B_TEST)
/* ================================================================== prueba
 * t3b_logros_test <logros.txt> <frames.bin> : frames.bin = N volcados de 32 MB (RA 0x0-0x1FFFFFF) */
static FILE *ff;
static long frame_off;
static int plat_open(unsigned long pid) { (void)pid; return 1; }
static int plat_find_ram(void) { return 1; }
static int plat_read(uint32_t off, uint8_t *dst, uint32_t size)
{
  fseek(ff, frame_off + (long)off, SEEK_SET);
  return fread(dst, 1, size, ff) == size;
}
static int plat_alive(void) { return 1; }
static int plat_in_game(void) { return 1; }
static double plat_now_ms(void) { return 0; }
static void plat_sleep_ms(double ms) { (void)ms; }
static void plat_start_stdin(void) {}
static void plat_describe(void) {}
int main(int argc, char **argv)
{
  int n, i, frames;
  long sz;
  if (argc < 3) return 2;
  rc_runtime_init(&runtime);
  n = load_defs(argv[1]);
  out("READY %u\n", (uint32_t)n, 0, 0);
  cache = malloc(RAM_SIZE); stamp = calloc(NPAGES, 4);
  ff = fopen(argv[2], "rb");
  if (!ff) return 3;
  fseek(ff, 0, SEEK_END); sz = ftell(ff);
  frames = (int)(sz / RAM_SIZE);
  for (i = 0; i < frames; i++) {
    frame_off = (long)i * RAM_SIZE;
    rc_runtime_do_frame(&runtime, on_event, peek, NULL, NULL);
    frame_no++;
  }
  (void)plat_open; (void)plat_find_ram; (void)plat_alive; (void)plat_in_game; (void)plat_now_ms; (void)plat_sleep_ms;
  (void)plat_start_stdin; (void)plat_describe;
  return 0;
}

#elif defined(_WIN32)
/* ================================================================== Windows */
#include <windows.h>

static HANDLE proc;
static DWORD gpid;
static HWND wnd;
static uint64_t mbase;
static LARGE_INTEGER qpf;

typedef struct { DWORD pid; HWND found; } find_t;
static BOOL CALLBACK enum_cb(HWND h, LPARAM lp)
{
  find_t *f = (find_t *)lp;
  char cls[32]; DWORD p = 0;
  GetWindowThreadProcessId(h, &p);
  if (p == f->pid && GetClassNameA(h, cls, sizeof cls) && strcmp(cls, "PPSSPPWnd") == 0) { f->found = h; return FALSE; }
  return TRUE;
}
static uint32_t msg32(UINT m, WPARAM w, LPARAM l)
{
  DWORD_PTR r = 0;
  if (!wnd || !SendMessageTimeoutA(wnd, m, w, l, SMTO_ABORTIFHUNG, 500, &r)) return 0;
  return (uint32_t)r;
}
static int plat_read(uint32_t off, uint8_t *dst, uint32_t size)
{
  SIZE_T got = 0;
  return mbase && ReadProcessMemory(proc, (LPCVOID)(uintptr_t)(mbase + 0x08000000ull + off), dst, size, &got) && got == size;
}
static int plat_in_game(void)
{
  /* WM_APP+0x3119: emulacion activa y en partida (no en el menu de PPSSPP) */
  static int last = 1; static uint32_t tick;
  if ((tick++ % 30) == 0) last = msg32(WM_APP + 0x3119, 0, 0) != 0;
  return last;
}
static int plat_find_ram(void)
{
  find_t f = { gpid, NULL };
  EnumWindows(enum_cb, (LPARAM)&f);
  if (!f.found) return 0;
  wnd = f.found;
  if (!msg32(WM_APP + 0x311A, 0, 0)) return 0;                   /* sin juego cargado todavia */
  mbase = ((uint64_t)msg32(WM_APP + 0x3118, 0, 1) << 32) | msg32(WM_APP + 0x3118, 0, 0);
  if (!mbase) return 0;
  {
    uint8_t b[4];
    return plat_read(0x00804000u, b, 4);                         /* el EBOOT se carga en 0x08804000 */
  }
}
static int plat_open(unsigned long pid)
{
  gpid = (DWORD)pid;
  QueryPerformanceFrequency(&qpf);
  proc = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, FALSE, gpid);
  { HMODULE wm = LoadLibraryA("winmm.dll"); if (wm) { typedef UINT(WINAPI *tbp_t)(UINT); tbp_t fn = (tbp_t)GetProcAddress(wm, "timeBeginPeriod"); if (fn) fn(1); } }
  return proc != NULL;
}
static int plat_alive(void)
{
  DWORD code = 0;
  return GetExitCodeProcess(proc, &code) && code == STILL_ACTIVE;
}
static double plat_now_ms(void)
{
  LARGE_INTEGER q; QueryPerformanceCounter(&q);
  return (double)q.QuadPart * 1000.0 / (double)qpf.QuadPart;
}
static void plat_sleep_ms(double ms) { if (ms >= 1) Sleep((DWORD)ms); }
static DWORD WINAPI stdin_thread(LPVOID u)
{
  char buf[256];
  (void)u;
  while (fgets(buf, sizeof buf, stdin))
    if (strncmp(buf, "QUIT", 4) == 0) break;
  quit_req = 1;
  return 0;
}
static void plat_start_stdin(void) { CreateThread(NULL, 0, stdin_thread, NULL, 0, NULL); }
static void plat_describe(void)
{
  char id[17] = {0}; int k;
  for (k = 0; k < 4; k++) { uint32_t v = msg32(WM_APP + 0x311A, k, 0); memcpy(id + 4 * k, &v, 4); }
  fprintf(stderr, "PPSSPP base=%llx juego=%s\n", (unsigned long long)mbase, id); fflush(stderr);
}

#elif defined(__linux__)
/* ================================================================== Linux */
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/types.h>

static int ram_fd = -1;
static off_t ram_off;
static pid_t root_pid, emu_pid;

static int plat_read(uint32_t off, uint8_t *dst, uint32_t size)
{
  return ram_fd >= 0 && pread(ram_fd, dst, size, ram_off + (off_t)off) == (ssize_t)size;
}
static int plat_in_game(void) { return 1; }
static pid_t parent_of(pid_t p)
{
  char path[64], buf[512]; FILE *f; int pp = 0;
  snprintf(path, sizeof path, "/proc/%d/stat", (int)p);
  if (!(f = fopen(path, "r"))) return 0;
  if (fgets(buf, sizeof buf, f)) { char *e = strrchr(buf, ')'); if (e) sscanf(e + 2, "%*c %d", &pp); }
  fclose(f);
  return (pid_t)pp;
}
static int descends(pid_t p)
{
  int guard = 0;
  while (p > 1 && guard++ < 64) { if (p == root_pid) return 1; p = parent_of(p); }
  return 0;
}
static int try_pid(pid_t p)
{
  char dir[64], link[300], target[512];
  DIR *d; struct dirent *e; int found = 0;
  snprintf(dir, sizeof dir, "/proc/%d/fd", (int)p);
  if (!(d = opendir(dir))) return 0;
  while (!found && (e = readdir(d))) {
    ssize_t n;
    if (e->d_name[0] == '.') continue;
    snprintf(link, sizeof link, "%s/%s", dir, e->d_name);
    n = readlink(link, target, sizeof target - 1);
    if (n <= 0) continue;
    target[n] = 0;
    if (!(strstr(target, "ppsspp_") && strstr(target, ".ram")) && !strstr(target, "gc_mem.tmp")) continue;
    {
      int fd = open(link, O_RDONLY | O_CLOEXEC);
      struct stat st; off_t o = -1;
      if (fd < 0) continue;
      if (fstat(fd, &st) == 0 && st.st_size >= (off_t)(0x204000 + RAM_SIZE)) {
        if ((st.st_size - 0x204000) % 0x100000 == 0) o = 0x204000;
        else if ((st.st_size - 0x214000) % 0x100000 == 0) o = 0x214000;   /* con pagina nula */
      }
      if (o >= 0) {
        uint8_t b[4] = {0};
        if (pread(fd, b, 4, o + 0x804000) == 4 && (b[0] | b[1] | b[2] | b[3])) {
          if (ram_fd >= 0) close(ram_fd);
          ram_fd = fd; ram_off = o; emu_pid = p; found = 1;
        } else close(fd);
      } else close(fd);
    }
  }
  closedir(d);
  return found;
}
static int scan_proc(int only_descendants)
{
  DIR *d; struct dirent *e; uid_t me = getuid(); int ok = 0;
  if (!(d = opendir("/proc"))) return 0;
  while (!ok && (e = readdir(d))) {
    char path[300]; struct stat st; pid_t p = (pid_t)atoi(e->d_name);
    if (p <= 1) continue;
    snprintf(path, sizeof path, "/proc/%s", e->d_name);
    if (stat(path, &st) != 0 || st.st_uid != me) continue;
    if (only_descendants && !descends(p)) continue;
    ok = try_pid(p);
  }
  closedir(d);
  return ok;
}
static int plat_find_ram(void)
{
  static int tries;
  if (try_pid(root_pid)) return 1;
  if (scan_proc(1)) return 1;
  return ++tries > 6 && scan_proc(0);   /* PPSSPP lanzado por otro camino (flatpak reparentado) */
}
static int plat_open(unsigned long pid) { root_pid = (pid_t)pid; return kill(root_pid, 0) == 0; }
static int plat_alive(void) { pid_t p = emu_pid ? emu_pid : root_pid; return kill(p, 0) == 0; }
static double plat_now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000.0 + t.tv_nsec / 1e6; }
static void plat_sleep_ms(double ms)
{
  struct timespec t; if (ms <= 0) return;
  t.tv_sec = (time_t)(ms / 1000); t.tv_nsec = (long)((ms - t.tv_sec * 1000.0) * 1e6);
  nanosleep(&t, NULL);
}
static void *stdin_thread(void *u)
{
  char buf[256]; (void)u;
  while (fgets(buf, sizeof buf, stdin)) if (strncmp(buf, "QUIT", 4) == 0) break;
  quit_req = 1;
  return NULL;
}
static void plat_start_stdin(void) { pthread_t t; pthread_create(&t, NULL, stdin_thread, NULL); pthread_detach(t); }
static void plat_describe(void) { fprintf(stderr, "PPSSPP pid=%d RAM@0x%llx\n", (int)emu_pid, (unsigned long long)ram_off); fflush(stderr); }
#endif
