# setup.ps1 - richtet "Pokemon im Claude-Browser" ein (Windows 10/11).
# Ohne -Consent wird NICHTS heruntergeladen oder installiert: es wird nur der Plan ausgegeben.
#   powershell -File setup.ps1            -> Plan/Status (Exit 0 = alles da, 10 = es fehlt etwas)
#   powershell -File setup.ps1 -Consent   -> fehlende Teile laden, installieren, bauen
#   powershell -File setup.ps1 -Consent -Rebuild   -> Spiel neu bauen
# Ausgabe-Zeilen fuer Programme: PENDING_MB=<n>, ADMIN_PROMPT=<True|False>, SETUP_OK, FEHLER:
param([switch]$Consent, [switch]$Rebuild)

$ErrorActionPreference = 'Continue'
if ($env:OS -ne 'Windows_NT') { Write-Host 'UNSUPPORTED: Dieses Plugin laeuft nur unter Windows.'; exit 1 }

$home_      = if ($env:POKEMON_IN_CLAUDE_HOME) { $env:POKEMON_IN_CLAUDE_HOME } else { Join-Path $env:LOCALAPPDATA 'pokemon-in-claude' }
$pluginRoot = Split-Path $PSScriptRoot -Parent
$patch      = Join-Path $pluginRoot 'patches\windows-browser.patch'
$srcDir     = Join-Path $home_ 'src\pokeemerald-wasm'
$depsDir    = Join-Path $home_ 'deps'
$binDir     = Join-Path $home_ 'bin'
$logDir     = Join-Path $home_ 'logs'
$wasmFile   = Join-Path $srcDir 'build\wasm\pokeemerald.wasm'

# Feste, geprueefte Quellen (Upstream-Stand und Pruefsummen)
$upstreamUrl = 'https://github.com/tripplyons/pokeemerald-wasm.git'
$upstreamSha = 'fd83f5b6e609b61b0b10777e32c74343e1a81b41'
$zlib = @{ File = 'zlib-1.3.2.tar.gz';    Dir = 'zlib-1.3.2';    Url = 'https://zlib.net/zlib-1.3.2.tar.gz'
           Sha = 'bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16' }
$png  = @{ File = 'libpng-1.6.59.tar.xz'; Dir = 'libpng-1.6.59'; Url = 'https://sourceforge.net/projects/libpng/files/libpng16/1.6.59/libpng-1.6.59.tar.xz/download'
           Sha = 'd80dd2a38a37f803cb9b6ac7b14bd6e74ddc3b654780a8380bdf93523fdb4389' }

# ---------- Werkzeug-Suche ----------
function First-Existing($paths) { foreach ($p in $paths) { if ($p -and (Test-Path $p)) { return $p } } return $null }
$wingetPkgs = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'

function Find-Git {
  $g = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $g) { return $null }
  $d = Split-Path $g.Source -Parent
  for ($i = 0; $i -lt 4; $i++) {
    if (Test-Path (Join-Path $d 'usr\bin\bash.exe')) { return @{ Exe = $g.Source; Root = $d } }
    $d = Split-Path $d -Parent
  }
  return $null
}
function Find-Mingw {
  $dirs = @()
  $dirs += Get-ChildItem $wingetPkgs -Directory -Filter 'BrechtSanders.WinLibs*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'mingw64\bin' }
  $g = Get-Command gcc.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($g) { $dirs += (Split-Path $g.Source -Parent) }
  foreach ($d in $dirs) {
    if ((Test-Path "$d\gcc.exe") -and (Test-Path "$d\g++.exe") -and (Test-Path "$d\mingw32-make.exe") -and (Test-Path "$d\cmake.exe")) { return $d }
  }
  return $null
}
function Find-Llvm {
  foreach ($d in @('C:\Program Files\LLVM\bin', (Join-Path $env:LOCALAPPDATA 'Programs\LLVM\bin'))) {
    if ((Test-Path "$d\clang.exe") -and (Test-Path "$d\wasm-ld.exe")) { return $d }
  }
  $c = Get-Command clang.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { $d = Split-Path $c.Source -Parent; if (Test-Path "$d\wasm-ld.exe") { return $d } }
  return $null
}
function Find-Uv {
  $c = Get-Command uv.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  $cands = @((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\uv.exe'), (Join-Path $env:USERPROFILE '.local\bin\uv.exe'))
  $cands += Get-ChildItem $wingetPkgs -Directory -Filter 'astral-sh.uv*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'uv.exe' }
  $cands += Get-ChildItem (Join-Path $env:APPDATA 'Python') -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'Scripts\uv.exe' }
  return (First-Existing $cands)
}
function Find-Node { $c = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { return $c.Source } return $null }

# ---------- Hilfen ----------
function Run([string]$what, [scriptblock]$cmd) {
  New-Item -ItemType Directory -Force $logDir | Out-Null
  $log = Join-Path $logDir 'setup.log'
  $out = & $cmd 2>&1
  $code = $LASTEXITCODE
  ("[{0}] {1} (Exit {2})" -f (Get-Date -Format s), $what, $code) | Add-Content $log
  $out | ForEach-Object { "$_" } | Add-Content $log
  if ($code -ne 0) { throw "$what fehlgeschlagen (Exit $code). Siehe $log" }
}
function Install-Winget([string]$id, [int]$timeoutMin) {
  $p = Start-Process winget -ArgumentList @('install', '--id', $id, '--exact', '--source', 'winget', '--silent', '--accept-package-agreements', '--accept-source-agreements') -PassThru -WindowStyle Hidden
  if (-not $p.WaitForExit($timeoutMin * 60000)) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    throw "Zeitueberschreitung bei $id nach $timeoutMin Minuten (haengt meist an der Windows-Admin-Abfrage UAC)."
  }
  if ($p.ExitCode -ne 0 -and $p.ExitCode -ne -1978335189) { throw "winget $id fehlgeschlagen (Exit $($p.ExitCode))." }
}
function Patch-Applied { if (-not (Test-Path (Join-Path $srcDir '.git'))) { return $false }; git -C $srcDir apply --check --reverse $patch 2>$null | Out-Null; return ($LASTEXITCODE -eq 0) }
function Source-Ready {
  if (-not (Test-Path (Join-Path $srcDir '.git'))) { return $false }
  $head = (git -C $srcDir rev-parse HEAD 2>$null | Out-String).Trim()
  return (($head -eq $upstreamSha) -and (Patch-Applied))
}

function Set-BuildEnv {
  $git = Find-Git; $mingw = Find-Mingw; $llvm = Find-Llvm; $uv = Find-Uv
  New-Item -ItemType Directory -Force $binDir | Out-Null
  Copy-Item (Join-Path $mingw 'mingw32-make.exe') (Join-Path $binDir 'make.exe') -Force
  $env:PATH = "$binDir;$($git.Root)\usr\bin;$($git.Root)\cmd;$llvm;$(Split-Path $uv -Parent);$mingw;$env:PATH"
  $env:C_INCLUDE_PATH = "$depsDir\include"; $env:CPLUS_INCLUDE_PATH = "$depsDir\include"; $env:LIBRARY_PATH = "$depsDir\lib"
  $env:PYTHONUTF8 = '1'
}

# ---------- Schritte ----------
function Build-Deps {
  Set-BuildEnv
  $dl = Join-Path $home_ 'downloads'
  New-Item -ItemType Directory -Force $dl, $depsDir | Out-Null
  foreach ($d in @($zlib, $png)) {
    $f = Join-Path $dl $d.File
    if (-not (Test-Path $f) -or ((Get-FileHash $f -Algorithm SHA256).Hash.ToLower() -ne $d.Sha)) {
      Invoke-WebRequest -Uri $d.Url -OutFile $f -UserAgent 'curl/8.5.0' -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 120
    }
    $got = (Get-FileHash $f -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $d.Sha) { Remove-Item $f -Force; throw "Pruefsumme falsch fuer $($d.File): $got" }
    if (-not (Test-Path (Join-Path $dl $d.Dir))) { Run "Entpacken $($d.File)" { & (Join-Path $env:SystemRoot 'System32\tar.exe') -xf $f -C $dl } }
  }
  $prefix = $depsDir -replace '\\', '/'
  $zsrc = Join-Path $dl $zlib.Dir; $zbld = Join-Path $dl 'build-zlib'
  $psrc = Join-Path $dl $png.Dir;  $pbld = Join-Path $dl 'build-libpng'
  Run 'zlib configure'  { cmake -S $zsrc -B $zbld -G 'MinGW Makefiles' -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=$prefix" -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_TESTING=OFF -DCMAKE_C_COMPILER=gcc }
  Run 'zlib build'      { cmake --build $zbld -j 4 }
  Run 'zlib install'    { cmake --install $zbld }
  Copy-Item (Join-Path $depsDir 'lib\libzs.a') (Join-Path $depsDir 'lib\libz.a') -Force
  Run 'libpng configure' { cmake -S $psrc -B $pbld -G 'MinGW Makefiles' -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=$prefix" "-DCMAKE_PREFIX_PATH=$prefix" "-DZLIB_ROOT=$prefix" "-DZLIB_LIBRARY=$prefix/lib/libz.a" "-DZLIB_INCLUDE_DIR=$prefix/include" -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DCMAKE_C_COMPILER=gcc }
  Run 'libpng build'    { cmake --build $pbld -j 4 }
  Run 'libpng install'  { cmake --install $pbld }
  Copy-Item (Join-Path $depsDir 'lib\libpng16.a') (Join-Path $depsDir 'lib\libpng.a') -Force
}

function Get-Source {
  New-Item -ItemType Directory -Force (Split-Path $srcDir -Parent) | Out-Null
  if (-not (Test-Path (Join-Path $srcDir '.git'))) {
    Run 'git init'        { git init -q $srcDir }
    Run 'git config'      { git -C $srcDir config core.autocrlf false }
    Run 'git remote add'  { git -C $srcDir remote add origin $upstreamUrl }
  }
  Run 'git fetch'    { git -C $srcDir fetch -q --depth 1 origin $upstreamSha }
  Run 'git checkout' { git -C $srcDir -c advice.detachedHead=false checkout -q --detach -f FETCH_HEAD }
  $head = (git -C $srcDir rev-parse HEAD | Out-String).Trim()
  if ($head -ne $upstreamSha) { throw "Falscher Upstream-Stand: $head" }
  Run 'Patch pruefen'    { git -C $srcDir apply --check $patch }
  Run 'Patch anwenden'   { git -C $srcDir apply $patch }
}

function Build-Game {
  Set-BuildEnv
  New-Item -ItemType Directory -Force $logDir | Out-Null
  $log = Join-Path $logDir 'build.log'
  Set-Location $srcDir
  $jflag = '-j' + [Math]::Min([int]$env:NUMBER_OF_PROCESSORS, 8)
  ("Start {0}, {1}" -f (Get-Date -Format s), $jflag) | Out-File $log -Encoding utf8
  $p = Start-Process cmd.exe -ArgumentList '/c', "make wasm $jflag CC=gcc WASM_CC=clang WASM_LD=wasm-ld >> `"$log`" 2>&1" -PassThru -WindowStyle Hidden
  $sw = [Diagnostics.Stopwatch]::StartNew(); $reason = $null
  while (-not $p.HasExited) {
    Start-Sleep 10
    $n = @(Get-Process make -ErrorAction SilentlyContinue).Count
    if ($n -gt 40)                       { $reason = "Wachhund: $n make-Prozesse (Endlos-Rekursion)"; break }
    if ($sw.Elapsed.TotalMinutes -gt 25) { $reason = 'Wachhund: 25 Minuten Zeitgrenze'; break }
  }
  if ($reason) {
    Get-Process make, clang, cc1, cc1plus, gcc, wasm-ld -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'generate_wasm|wasm_asm_data' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    throw "$reason. Siehe $log"
  }
  $p.WaitForExit()
  ("ENDE {0}, Exit-Code {1}" -f (Get-Date -Format s), $p.ExitCode) | Out-File $log -Append -Encoding utf8
  if ($p.ExitCode -ne 0 -or -not (Test-Path $wasmFile)) { throw "Bau fehlgeschlagen. Siehe $log" }
}

# ---------- Plan ----------
$git = Find-Git
if (-not $git) { Write-Host 'GIT_MISSING: Git for Windows fehlt. Bitte installieren (winget install Git.Git) und /pokemon erneut starten.'; exit 1 }

$steps = @()
function Add-Step($id, $label, $done, $mb, $admin, $action) { $script:steps += [pscustomobject]@{ Id = $id; Label = $label; Done = [bool]$done; MB = $mb; Admin = $admin; Action = $action } }
Add-Step 'node'  'Node.js (winget OpenJS.NodeJS.LTS)'                         ([bool](Find-Node))  30  $true  { Install-Winget 'OpenJS.NodeJS.LTS' 10 }
Add-Step 'gcc'   'MinGW-Compiler WinLibs (winget BrechtSanders.WinLibs)'       ([bool](Find-Mingw)) 261 $false { Install-Winget 'BrechtSanders.WinLibs.POSIX.UCRT' 20 }
Add-Step 'llvm'  'LLVM mit clang und wasm-ld (winget LLVM.LLVM)'               ([bool](Find-Llvm))  610 $true  { Install-Winget 'LLVM.LLVM' 20 }
Add-Step 'uv'    'uv fuer Python-Skripte (winget astral-sh.uv, laedt beim ersten Lauf noch ca. 30 MB Python)' ([bool](Find-Uv)) 17 $false { Install-Winget 'astral-sh.uv' 10 }
Add-Step 'deps'  'zlib 1.3.2 und libpng 1.6.59 (Quellcode, mit Pruefsumme, wird selbst gebaut)' (Test-Path (Join-Path $depsDir 'lib\libpng.a')) 3 $false { Build-Deps }
Add-Step 'src'   "Spiel-Quellcode tripplyons/pokeemerald-wasm @ $($upstreamSha.Substring(0,8)) plus Windows-Patch" (Source-Ready) 55 $false { Get-Source }
Add-Step 'build' 'Spiel bauen (make wasm, ca. 5 Minuten)'                      ((Test-Path $wasmFile) -and -not $Rebuild) 0 $false { Build-Game }

$pending = @($steps | Where-Object { -not $_.Done })
Write-Host "PLAN:"
foreach ($s in $steps) {
  $mark = if ($s.Done) { '[x]' } else { '[ ]' }
  $extra = ''
  if (-not $s.Done) { if ($s.MB -gt 0) { $extra += " (ca. $($s.MB) MB)" }; if ($s.Admin) { $extra += ' [Admin-Abfrage]' } }
  Write-Host ("  {0} {1}{2}" -f $mark, $s.Label, $extra)
}
$pendingMB = 0; foreach ($s in $pending) { $pendingMB += [int]$s.MB }
$adminNeeded = [bool](@($pending | Where-Object { $_.Admin }).Count)
Write-Host "PENDING_MB=$pendingMB"
Write-Host "ADMIN_PROMPT=$adminNeeded"

if (-not $Consent) {
  if ($pending.Count -eq 0) { Write-Host 'SETUP_OK: Alles vorhanden.'; exit 0 }
  Write-Host 'Nur Plan. Zum Ausfuehren: setup.ps1 -Consent'
  exit 10
}

# ---------- Ausfuehren ----------
foreach ($s in $pending) {
  Write-Host ">> $($s.Label)"
  if ($s.Admin) { Write-Host 'ACHTUNG: Gleich erscheint eine Windows-Abfrage (UAC). Bitte "Ja" klicken.' }
  try { & $s.Action } catch { Write-Host "FEHLER: $($_.Exception.Message)"; exit 20 }
}
if (Test-Path $wasmFile) { Write-Host ("SETUP_OK: {0:N1} MB" -f ((Get-Item $wasmFile).Length / 1MB)); exit 0 }
Write-Host 'FEHLER: pokeemerald.wasm fehlt nach dem Bau.'; exit 20
