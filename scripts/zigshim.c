/* zigshim.c - startet "zig cc" bzw. "zig wasm-ld" unter dem Namen clang.exe / wasm-ld.exe.
 *
 * Das Spiel-Makefile ruft "clang --target=wasm32-unknown-unknown ..." und "wasm-ld ..." auf.
 * Zig kennt das Ziel unter dem Namen wasm32-freestanding. Dieses kleine Programm
 *   - uebersetzt nur das Ziel,
 *   - schaltet Debug-Informationen ab (-g0, sonst wird die .wasm-Datei rund 8 MB groesser),
 *   - gleicht zwei Zig-Eigenheiten an normales clang an (-UNDEBUG, -fhosted), damit das Spiel
 *     gleich uebersetzt wird wie mit LLVM,
 *   - reicht alles andere unveraendert (inklusive stdin/stdout/stderr) an zig weiter.
 *
 * zig.exe wird ueber die Umgebungsvariable POKEMON_ZIG gefunden, sonst unter ..\zig\zig.exe.
 * Bauen (MinGW):  gcc -O2 -municode -s zigshim.c -o clang.exe
 */
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
#include <string.h>

#define PATH_CAP 32768
#define CMD_CAP  32768

static int overflow = 0;

static void put(wchar_t *buf, size_t *n, const wchar_t *s) {
  size_t l = wcslen(s);
  if (*n + l + 1 >= CMD_CAP) { overflow = 1; return; }
  memcpy(buf + *n, s, l * sizeof(wchar_t));
  *n += l;
  buf[*n] = 0;
}

/* Haengt ein Argument mit den Quoting-Regeln von Windows an die Kommandozeile an. */
static void put_arg(wchar_t *buf, size_t *n, const wchar_t *a) {
  put(buf, n, L" ");
  if (*a && !wcspbrk(a, L" \t\"")) { put(buf, n, a); return; }
  put(buf, n, L"\"");
  for (const wchar_t *p = a;; p++) {
    size_t bs = 0;
    while (*p == L'\\') { bs++; p++; }
    if (!*p) { for (size_t i = 0; i < bs * 2; i++) put(buf, n, L"\\"); break; }
    if (*p == L'"') { for (size_t i = 0; i < bs * 2 + 1; i++) put(buf, n, L"\\"); put(buf, n, L"\""); }
    else { for (size_t i = 0; i < bs; i++) put(buf, n, L"\\"); wchar_t t[2] = { *p, 0 }; put(buf, n, t); }
  }
  put(buf, n, L"\"");
}

int wmain(int argc, wchar_t **argv) {
  wchar_t *self = (wchar_t *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, PATH_CAP * sizeof(wchar_t));
  wchar_t *zig  = (wchar_t *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, PATH_CAP * sizeof(wchar_t));
  wchar_t *cmd  = (wchar_t *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, CMD_CAP * sizeof(wchar_t));
  if (!self || !zig || !cmd) { fputs("zigshim: Speicher nicht verfuegbar\n", stderr); return 1; }

  DWORD sl = GetModuleFileNameW(NULL, self, PATH_CAP);
  if (!sl || sl >= PATH_CAP) { fputs("zigshim: eigener Pfad nicht lesbar oder zu lang\n", stderr); return 1; }
  wchar_t *slash = wcsrchr(self, L'\\');
  const wchar_t *base = slash ? slash + 1 : self;
  int is_ld = (_wcsnicmp(base, L"wasm-ld", 7) == 0);

  DWORD got = GetEnvironmentVariableW(L"POKEMON_ZIG", zig, PATH_CAP);
  if (!got || got >= PATH_CAP) {
    if (slash) *slash = 0;
    if (wcslen(self) + 20 >= PATH_CAP) { fputs("zigshim: Pfad zu lang\n", stderr); return 1; }
    wcscpy(zig, self);
    wcscat(zig, L"\\..\\zig\\zig.exe");
  }

  size_t n = 0;
  put(cmd, &n, L"\""); put(cmd, &n, zig); put(cmd, &n, L"\"");
  put(cmd, &n, is_ld ? L" wasm-ld" : L" cc");

  int has_g = 0;
  for (int i = 1; i < argc; i++) {
    if (!is_ld && argv[i][0] == L'-' && argv[i][1] == L'g') has_g = 1;
    if (!is_ld && wcscmp(argv[i], L"--target=wasm32-unknown-unknown") == 0) put_arg(cmd, &n, L"--target=wasm32-freestanding");
    else put_arg(cmd, &n, argv[i]);
  }
  if (!is_ld && !has_g) put_arg(cmd, &n, L"-g0");
  /* Zig definiert von sich aus NDEBUG und meldet eine Umgebung ohne Standardbibliothek (freestanding).
   * Beides gleichen wir an normales clang an. */
  if (!is_ld) { put_arg(cmd, &n, L"-UNDEBUG"); put_arg(cmd, &n, L"-fhosted"); }
  if (overflow) { fputs("zigshim: Kommandozeile zu lang\n", stderr); return 1; }

  STARTUPINFOW si; PROCESS_INFORMATION pi;
  ZeroMemory(&si, sizeof si); si.cb = sizeof si;
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  if (!CreateProcessW(NULL, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) { fputs("zigshim: zig.exe nicht startbar\n", stderr); return 127; }
  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 1; GetExitCodeProcess(pi.hProcess, &code);
  return (int)code;
}
