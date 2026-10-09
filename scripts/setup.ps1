# setup.ps1 - richtet "Pokemon im Claude-Browser" ein (Windows 10/11). Keine Administratorrechte noetig.
# Ohne -Consent wird NICHTS heruntergeladen oder installiert: es wird nur der Plan ausgegeben.
#   powershell -File setup.ps1            -> Plan/Status (Exit 0, Zustand in der Zeile SETUP_STATE=READY oder PENDING)
#   powershell -File setup.ps1 -Consent   -> fehlende Teile parallel laden, entpacken, bauen (bei Abbruch einfach erneut starten)
#   powershell -File setup.ps1 -Consent -Rebuild   -> Spiel neu bauen
# Ausgabe-Zeilen fuer Programme: SETUP_STATE=<READY|PENDING>, PENDING_MB=<n>, SETUP_OK, FEHLER:
param([switch]$Consent, [switch]$Rebuild)

$ErrorActionPreference = 'Continue'
if ($env:OS -ne 'Windows_NT') { Write-Host 'UNSUPPORTED: Dieses Plugin laeuft nur unter Windows.'; exit 1 }

$homeRaw    = if ($env:POKEMON_IN_CLAUDE_HOME) { $env:POKEMON_IN_CLAUDE_HOME } else { Join-Path $env:LOCALAPPDATA 'pokemon-in-claude' }
$home_      = [IO.Path]::GetFullPath($homeRaw).TrimEnd('\')
$homeMarker = Join-Path $home_ '.pokemon-in-claude'
$pluginRoot = Split-Path $PSScriptRoot -Parent
$patch      = Join-Path $pluginRoot 'patches\windows-browser.patch'
$shimSrc    = Join-Path $PSScriptRoot 'zigshim.c'
$dl         = Join-Path $home_ '_dl'
$zigDir     = Join-Path $home_ 'zig'
$gccDir     = Join-Path $home_ 'winlibs'
$gccBin     = Join-Path $gccDir 'mingw64\bin'
$uvDir      = Join-Path $home_ 'uv'
$nodeDir    = Join-Path $home_ 'node'
$depsDir    = Join-Path $home_ 'deps'
$binDir     = Join-Path $home_ 'bin'
$logDir     = Join-Path $home_ 'logs'
$srcDir     = Join-Path $home_ 'src\pokeemerald-wasm'
$wasmFile   = Join-Path $srcDir 'build\wasm\pokeemerald.wasm'
$shimStamp  = Join-Path $binDir 'shim.sha256'

# Feste, geprueefte Quellen (Download-Adresse und SHA-256-Pruefsumme)
$upstreamUrl = 'https://github.com/tripplyons/pokeemerald-wasm.git'
$upstreamSha = 'fd83f5b6e609b61b0b10777e32c74343e1a81b41'
$assets = @{
  zig  = @{ File = 'zig-x86_64-windows-0.17.0.zip'; MB = 96; Dest = $zigDir; Rel = 'zig.exe'
            Url = 'https://ziglang.org/download/0.17.0/zig-x86_64-windows-0.17.0.zip'
            Sha = 'b5663f69581dcf391293fbf16c06cb80d81d806545ce618b4d0bab7f0eb8c428' }
  gcc  = @{ File = 'winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r2.7z'; MB = 105; Dest = $gccDir; Rel = 'mingw64\bin\gcc.exe'
            Url = 'https://github.com/brechtsanders/winlibs_mingw/releases/download/16.2.0posix-14.0.0-ucrt-r2/winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r2.7z'
            Sha = '53fb6773fbdf87cdf22b69a6b2a07ee33d3ada413b42d83044bc7cc6481400d2' }
  uv   = @{ File = 'uv-x86_64-pc-windows-msvc-0.12.23.zip'; MB = 17; Dest = $uvDir; Rel = 'uv.exe'
            Url = 'https://github.com/astral-sh/uv/releases/download/0.12.23/uv-x86_64-pc-windows-msvc.zip'
            Sha = '75d05de6762778c31ee183398de7dd15093fad0ed90b1f236d8205ea5ec00c90' }
  node = @{ File = 'node-v24.21.0-win-x64.zip'; MB = 36; Dest = $nodeDir; Rel = 'node.exe'
            Url = 'https://nodejs.org/dist/v24.21.0/node-v24.21.0-win-x64.zip'
            Sha = '158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541' }
  zlib = @{ File = 'zlib-1.3.2.tar.gz'; MB = 2; Dest = $null; Dir = 'zlib-1.3.2'
            Url = 'https://zlib.net/zlib-1.3.2.tar.gz'
            Alt = 'https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz'
            Sha = 'bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16' }
}
# libpng kommt per git von GitHub (fester Commit von Tag v1.6.59), nicht als Archiv
$pngUrl = 'https://github.com/pnggroup/libpng.git'
$pngSha = 'cd952f49f95bb27154ae77dbb103032d95f6e580'

# ---------- Hilfen ----------
function Q([string]$s) { return '"' + $s + '"' }
function Sha([string]$f) { return (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLower() }
function UnderHome([string]$p) { return ([IO.Path]::GetFullPath($p)).StartsWith($home_ + '\', [StringComparison]::OrdinalIgnoreCase) }
function Remove-Tree([string]$p) {
  if (-not (UnderHome $p)) { throw "Loeschen ausserhalb des Plugin-Ordners verweigert: $p" }
  if (-not (Test-Path -LiteralPath $p)) { return }
  Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
  [IO.Directory]::Delete($p, $true)
}

# Schutz: Das Home darf nie ein Laufwerk, ein Windows- oder Profilordner sein, und ein vorhandener fremder, nicht leerer Ordner wird abgelehnt.
function Check-Home {
  $protected = @([IO.Path]::GetPathRoot($home_).TrimEnd('\'), $env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:windir, $env:SystemRoot, $env:TEMP,
                 (Join-Path $env:USERPROFILE 'Documents'), (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop')) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
  if ($protected -contains $home_) { return "Der Ordner $home_ ist ein Systemordner und kein Platz fuer das Plugin." }
  if ((Test-Path -LiteralPath $home_) -and -not (Test-Path -LiteralPath $homeMarker) -and ((Split-Path $home_ -Leaf) -ne 'pokemon-in-claude')) {
    if (@(Get-ChildItem -LiteralPath $home_ -Force -ErrorAction SilentlyContinue).Count -gt 0) { return "Der Ordner $home_ ist nicht leer und gehoert nicht zu diesem Plugin." }
  }
  return $null
}

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
# Ein vorhandenes Node zaehlt nur ab Version 18 (aeltere koennen den Spielserver nicht starten); sonst wird ein eigenes geladen.
function Node-Ok([string]$exe) { try { $v = (& $exe --version 2>$null | Out-String).Trim(); return ($v -match '^v(\d+)\.' -and [int]$Matches[1] -ge 18) } catch { return $false } }
function Node-Exe { $own = Join-Path $nodeDir 'node.exe'; if (Test-Path $own) { return $own }; $c = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c -and (Node-Ok $c.Source)) { return $c.Source }; return $null }
function Uv-Exe   { $own = Join-Path $uvDir 'uv.exe';     if (Test-Path $own) { return $own }; $c = Get-Command uv.exe   -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { return $c.Source }; return $null }
function Tool-Done($id) {
  $a = $assets[$id]
  if ($id -eq 'node') { return [bool](Node-Exe) }
  if ($id -eq 'uv')   { return [bool](Uv-Exe) }
  return (Test-Path (Join-Path $a.Dest $a.Rel))   # Zielordner entsteht erst nach vollstaendigem Entpacken (Umbenennen)
}
function Shim-Done {
  if (-not (Test-Path $shimStamp)) { return $false }
  foreach ($f in 'clang.exe', 'wasm-ld.exe', 'make.exe') { if (-not (Test-Path (Join-Path $binDir $f))) { return $false } }
  return ((Get-Content $shimStamp -Raw).Trim() -eq (Sha $shimSrc))
}
function Patch-Applied { if (-not (Test-Path (Join-Path $srcDir '.git'))) { return $false }; git -C $srcDir apply --check --reverse $patch 2>$null | Out-Null; return ($LASTEXITCODE -eq 0) }
function Source-Ready {
  if (-not (Test-Path (Join-Path $srcDir '.git'))) { return $false }
  $head = (git -C $srcDir rev-parse HEAD 2>$null | Out-String).Trim()
  return (($head -eq $upstreamSha) -and (Patch-Applied))
}

function Run([string]$what, [scriptblock]$cmd) {
  New-Item -ItemType Directory -Force $logDir | Out-Null
  $log = Join-Path $logDir 'setup.log'
  $global:LASTEXITCODE = $null
  $out = & $cmd 2>&1
  $code = $LASTEXITCODE
  if ($null -eq $code) { $code = 1 }   # Programm nicht gefunden oder nicht gestartet
  ("[{0}] {1} (Exit {2})" -f (Get-Date -Format s), $what, $code) | Add-Content $log
  $out | ForEach-Object { "$_" } | Add-Content $log
  if ($code -ne 0) { throw "$what fehlgeschlagen (Exit $code). Siehe $log" }
}

function Set-BuildEnv {
  $git = Find-Git; $uv = Uv-Exe
  $env:POKEMON_ZIG = Join-Path $zigDir 'zig.exe'
  $env:ZIG_GLOBAL_CACHE_DIR = Join-Path $home_ 'zig-cache'
  $env:NoDefaultCurrentDirectoryInExePath = '1'   # Programme nie aus dem Arbeitsordner (dem Spiel-Repo) starten
  $env:PATH = "$binDir;$($git.Root)\usr\bin;$($git.Root)\cmd;$(Split-Path $uv -Parent);$gccBin;$env:PATH"
  $env:C_INCLUDE_PATH = "$depsDir\include"; $env:CPLUS_INCLUDE_PATH = "$depsDir\include"; $env:LIBRARY_PATH = "$depsDir\lib"
  $env:PYTHONUTF8 = '1'
}

# Prozess und alle seine Nachkommen (nur die eigenen, nicht fremde make/gcc/zig des Nutzers)
function Get-Tree([int]$rootId) {
  $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
  $ids = New-Object System.Collections.Generic.List[int]; $ids.Add($rootId); $i = 0
  while ($i -lt $ids.Count) { $cur = $ids[$i]; $i++; foreach ($c in $all) { if ($c.ParentProcessId -eq $cur -and -not $ids.Contains([int]$c.ProcessId)) { $ids.Add([int]$c.ProcessId) } } }
  return @($all | Where-Object { $ids.Contains([int]$_.ProcessId) })
}

# ---------- Schritte ----------
# 1) Alles Fehlende gleichzeitig laden (curl.exe) und den Spiel-Quellcode per git holen
function Fetch-All([string[]]$ids, [bool]$needSource) {
  New-Item -ItemType Directory -Force $dl | Out-Null
  $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
  if (-not (Test-Path $curl)) { throw 'curl.exe fehlt (Windows 10 ab Version 1803 noetig).' }
  $jobs = @(); $gitP = $null
  try {
    foreach ($id in $ids) {
      $a = $assets[$id]; $f = Join-Path $dl $a.File
      if ((Test-Path $f) -and ((Sha $f) -eq $a.Sha)) { continue }
      $args_ = '--proto =https --proto-redir =https --max-redirs 5 -L --fail --silent --show-error --retry 5 --retry-all-errors --retry-delay 2 -o ' + (Q $f) + ' ' + (Q $a.Url)
      $p = Start-Process $curl -ArgumentList $args_ -PassThru -WindowStyle Hidden; $null = $p.Handle
      $jobs += [pscustomobject]@{ Id = $id; A = $a; File = $f; P = $p }
    }
    if ($needSource) {
      New-Item -ItemType Directory -Force (Split-Path $srcDir -Parent) | Out-Null
      if (-not (Test-Path (Join-Path $srcDir '.git'))) { Run 'git init' { git init -q $srcDir }; Run 'git config' { git -C $srcDir config core.autocrlf false } }
      git -C $srcDir remote get-url origin 2>$null | Out-Null
      if ($LASTEXITCODE -ne 0) { Run 'git remote add' { git -C $srcDir remote add origin $upstreamUrl } }
      New-Item -ItemType Directory -Force $logDir | Out-Null
      $gitArgs = '-C ' + (Q $srcDir) + ' fetch -q --depth 1 origin ' + $upstreamSha
      $gitP = Start-Process git -ArgumentList $gitArgs -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $logDir 'git-fetch.log'); $null = $gitP.Handle
    }
    $total = $jobs.Count + $(if ($gitP) { 1 } else { 0 })
    $sw = [Diagnostics.Stopwatch]::StartNew(); $last = -15
    while ($true) {
      $running = @($jobs | Where-Object { -not $_.P.HasExited }).Count + $(if ($gitP -and -not $gitP.HasExited) { 1 } else { 0 })
      if ($running -eq 0) { break }
      if ($sw.Elapsed.TotalSeconds - $last -ge 15) {
        $mb = 0; foreach ($j in $jobs) { if (Test-Path $j.File) { $mb += (Get-Item $j.File).Length / 1MB } }
        Write-Host ("  Downloads laufen: {0} von {1} fertig, {2:N0} MB geladen ({3:N0} s)" -f ($total - $running), $total, $mb, $sw.Elapsed.TotalSeconds)
        $last = $sw.Elapsed.TotalSeconds
      }
      if ($sw.Elapsed.TotalMinutes -gt 30) { throw 'Downloads brauchen laenger als 30 Minuten, abgebrochen.' }
      Start-Sleep -Seconds 2
    }
    foreach ($j in $jobs) {
      if ($j.P.ExitCode -ne 0 -and $j.A.Alt) {   # zweite Quelle versuchen
        Write-Host "  $($j.A.File): erste Quelle fehlgeschlagen, versuche zweite"
        $p2 = Start-Process $curl -ArgumentList ('--proto =https --proto-redir =https --max-redirs 5 -L --fail --silent --show-error --retry 5 --retry-all-errors -o ' + (Q $j.File) + ' ' + (Q $j.A.Alt)) -PassThru -WindowStyle Hidden -Wait
        $j.P = $p2; $null = $p2.Handle
      }
      if ($j.P.ExitCode -ne 0) { throw "Download fehlgeschlagen: $($j.A.File) (curl Exit $($j.P.ExitCode))" }
      $got = Sha $j.File
      if ($got -ne $j.A.Sha) { [IO.File]::Delete($j.File); throw "Pruefsumme falsch fuer $($j.A.File): $got" }
    }
    if ($gitP -and $gitP.ExitCode -ne 0) { throw "git fetch fehlgeschlagen. Siehe $logDir\git-fetch.log" }
    Write-Host ("  Downloads fertig in {0:N0} s." -f $sw.Elapsed.TotalSeconds)
  } finally {
    foreach ($j in $jobs) { if ($j.P -and -not $j.P.HasExited) { Stop-Process -Id $j.P.Id -Force -ErrorAction SilentlyContinue } }
    if ($gitP -and -not $gitP.HasExited) { Stop-Process -Id $gitP.Id -Force -ErrorAction SilentlyContinue }
  }
}

# 2) Archive gleichzeitig entpacken (Windows-eigenes tar.exe, kann zip, tar.gz, tar.xz und 7z).
#    Werkzeuge werden in einen .tmp-Ordner entpackt und erst danach umbenannt: ein halber Ordner gilt nie als fertig.
function Extract-All([string[]]$ids) {
  $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
  $jobs = @()
  try {
    foreach ($id in $ids) {
      $a = $assets[$id]; $f = Join-Path $dl $a.File
      if ($a.Dest) { $to = $a.Dest + '.tmp'; Remove-Tree $to; New-Item -ItemType Directory -Force $to | Out-Null }
      else { $to = $dl; Remove-Tree (Join-Path $dl $a.Dir) }   # Quellordner immer frisch entpacken
      $p = Start-Process $tar -ArgumentList ('-xf ' + (Q $f) + ' -C ' + (Q $to)) -PassThru -WindowStyle Hidden; $null = $p.Handle
      $jobs += [pscustomobject]@{ Id = $id; A = $a; To = $to; P = $p }
    }
    foreach ($j in $jobs) { $j.P.WaitForExit() }
    foreach ($j in $jobs) {
      if ($j.P.ExitCode -ne 0) { throw "Entpacken fehlgeschlagen: $($j.A.File) (tar Exit $($j.P.ExitCode))" }
      if ($j.A.Dest) {
        $tmp = $j.To
        if (-not (Test-Path (Join-Path $tmp $j.A.Rel))) {   # Inhalt liegt eine Ebene tiefer (z. B. zig-x86_64-windows-0.17.0\)
          $sub = Get-ChildItem $tmp -Directory | Where-Object { Test-Path (Join-Path $_.FullName $j.A.Rel) } | Select-Object -First 1
          if ($sub) { Get-ChildItem $sub.FullName -Force | ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $tmp -Force -ErrorAction Stop }; [IO.Directory]::Delete($sub.FullName, $true) }
        }
        if (-not (Test-Path (Join-Path $tmp $j.A.Rel))) { throw "Nach dem Entpacken fehlt $($j.A.Rel) in $tmp" }
        Remove-Tree $j.A.Dest
        $moved = $false
        for ($k = 0; $k -lt 10 -and -not $moved; $k++) { try { [IO.Directory]::Move($tmp, $j.A.Dest); $moved = $true } catch { Start-Sleep -Seconds 1 } }
        if (-not $moved) { throw "Umbenennen fehlgeschlagen: $tmp (Virenscanner?)" }
      } elseif (-not (Test-Path (Join-Path $dl $j.A.Dir))) { throw "Nach dem Entpacken fehlt der Ordner $($j.A.Dir)" }
    }
  } finally {
    foreach ($j in $jobs) { if ($j.P -and -not $j.P.HasExited) { Stop-Process -Id $j.P.Id -Force -ErrorAction SilentlyContinue } }
  }
}

# 3) Hilfsprogramme clang.exe / wasm-ld.exe (leiten an Zig weiter) und make.exe
function Build-Shims {
  New-Item -ItemType Directory -Force $binDir | Out-Null
  $gcc = Join-Path $gccBin 'gcc.exe'
  Run 'zigshim kompilieren' { & $gcc -O2 -municode -s $shimSrc -o (Join-Path $binDir 'clang.exe') }
  Copy-Item (Join-Path $binDir 'clang.exe') (Join-Path $binDir 'wasm-ld.exe') -Force -ErrorAction Stop
  Copy-Item (Join-Path $gccBin 'mingw32-make.exe') (Join-Path $binDir 'make.exe') -Force -ErrorAction Stop
  (Sha $shimSrc) | Set-Content $shimStamp
}

# libpng-Quellcode per git auf den festen Commit holen (git prueft den Inhalt ueber die Commit-Nummer)
function Fetch-Png([string]$dir) {
  Remove-Tree $dir
  New-Item -ItemType Directory -Force $dir | Out-Null
  Run 'libpng git init'     { git init -q $dir }
  Run 'libpng git remote'   { git -C $dir remote add origin $pngUrl }
  Run 'libpng git fetch'    { git -C $dir fetch -q --depth 1 origin $pngSha }
  Run 'libpng git checkout' { git -C $dir -c advice.detachedHead=false checkout -q --detach -f FETCH_HEAD }
  $head = (git -C $dir rev-parse HEAD | Out-String).Trim()
  if ($head -ne $pngSha) { throw "Falscher libpng-Stand: $head" }
}

# 4) zlib und libpng aus dem Quellcode bauen (fuer das Werkzeug gbagfx)
function Build-Deps {
  Set-BuildEnv
  New-Item -ItemType Directory -Force $depsDir | Out-Null
  $prefix = $depsDir -replace '\\', '/'
  $zsrc = Join-Path $dl $assets.zlib.Dir; $zbld = Join-Path $dl 'build-zlib'
  $psrc = Join-Path $dl 'libpng-src';     $pbld = Join-Path $dl 'build-libpng'
  Fetch-Png $psrc
  Run 'zlib configure'   { cmake -S $zsrc -B $zbld -G 'MinGW Makefiles' -DCMAKE_SH=CMAKE_SH-NOTFOUND -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=$prefix" -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_TESTING=OFF -DCMAKE_C_COMPILER=gcc }
  Run 'zlib build'       { cmake --build $zbld -j 4 }
  Run 'zlib install'     { cmake --install $zbld }
  Copy-Item (Join-Path $depsDir 'lib\libzs.a') (Join-Path $depsDir 'lib\libz.a') -Force -ErrorAction Stop
  Run 'libpng configure' { cmake -S $psrc -B $pbld -G 'MinGW Makefiles' -DCMAKE_SH=CMAKE_SH-NOTFOUND -DCMAKE_BUILD_TYPE=Release "-DCMAKE_INSTALL_PREFIX=$prefix" "-DCMAKE_PREFIX_PATH=$prefix" "-DZLIB_ROOT=$prefix" "-DZLIB_LIBRARY=$prefix/lib/libz.a" "-DZLIB_INCLUDE_DIR=$prefix/include" -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DCMAKE_C_COMPILER=gcc }
  Run 'libpng build'     { cmake --build $pbld -j 4 }
  Run 'libpng install'   { cmake --install $pbld }
  Copy-Item (Join-Path $depsDir 'lib\libpng16.a') (Join-Path $depsDir 'lib\libpng.a') -Force -ErrorAction Stop   # libpng.a zuletzt: gilt als "fertig"
}

# 5) Quellcode auschecken und den Windows-Patch anwenden
function Finish-Source {
  Run 'git checkout' { git -C $srcDir -c advice.detachedHead=false checkout -q --detach -f FETCH_HEAD }
  $head = (git -C $srcDir rev-parse HEAD | Out-String).Trim()
  if ($head -ne $upstreamSha) { throw "Falscher Upstream-Stand: $head" }
  Run 'Patch pruefen'  { git -C $srcDir apply --check $patch }
  Run 'Patch anwenden' { git -C $srcDir apply $patch }
}

# 6) Spiel bauen (mit Wachhund gegen Endlos-Rekursion und Haenger; er beendet nur die eigene Prozess-Gruppe)
function Build-Game {
  Set-BuildEnv
  New-Item -ItemType Directory -Force $logDir | Out-Null
  $log = Join-Path $logDir 'build.log'
  if (Test-Path -LiteralPath $wasmFile) { [IO.File]::Delete($wasmFile) }   # nie mit einer alten oder halben Datei weiterarbeiten
  $jflag = '-j' + [Math]::Min([int]$env:NUMBER_OF_PROCESSORS, 8)
  ("Start {0}, {1}" -f (Get-Date -Format s), $jflag) | Out-File $log -Encoding utf8
  $p = Start-Process cmd.exe -ArgumentList '/c', ("make wasm $jflag CC=gcc WASM_CC=clang WASM_LD=wasm-ld >> " + (Q $log) + ' 2>&1') -WorkingDirectory $srcDir -PassThru -WindowStyle Hidden
  $null = $p.Handle
  $sw = [Diagnostics.Stopwatch]::StartNew(); $reason = $null; $lastN = -60
  while (-not $p.HasExited) {
    Start-Sleep -Seconds 5
    $n = @(Get-Tree $p.Id | Where-Object { $_.Name -ieq 'make.exe' }).Count
    if ($n -gt 40)                       { $reason = "Wachhund: $n make-Prozesse (Endlos-Rekursion)"; break }
    if ($sw.Elapsed.TotalMinutes -gt 30) { $reason = 'Wachhund: 30 Minuten Zeitgrenze'; break }
    if ($sw.Elapsed.TotalSeconds - $lastN -ge 60) { Write-Host ("  Bau laeuft ({0:N0} s)" -f $sw.Elapsed.TotalSeconds); $lastN = $sw.Elapsed.TotalSeconds }
  }
  if ($reason) {
    & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /T /F /PID $p.Id 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    if (Test-Path -LiteralPath $wasmFile) { [IO.File]::Delete($wasmFile) }
    throw "$reason. Siehe $log"
  }
  $p.WaitForExit()
  ("ENDE {0}, Exit-Code {1}, Bauzeit {2:N0} s" -f (Get-Date -Format s), $p.ExitCode, $sw.Elapsed.TotalSeconds) | Out-File $log -Append -Encoding utf8
  if ($p.ExitCode -ne 0 -or -not (Test-Path $wasmFile)) { if (Test-Path -LiteralPath $wasmFile) { [IO.File]::Delete($wasmFile) }; throw "Bau fehlgeschlagen. Siehe $log" }
}

# ---------- Plan ----------
$homeProblem = Check-Home
if ($homeProblem) { Write-Host "HOME_UNSAFE: $homeProblem"; exit 1 }
$git = Find-Git
if (-not $git) { Write-Host 'GIT_MISSING: Git for Windows fehlt. Bitte installieren (winget install Git.Git) und /pokemon erneut starten.'; exit 1 }

$steps = @()
function Add-Step($id, $label, $done, $mb) { $script:steps += [pscustomobject]@{ Id = $id; Label = $label; Done = [bool]$done; MB = $mb } }
Add-Step 'zig'   'Zig 0.17.0 (Compiler fuer WebAssembly)'                                  (Tool-Done 'zig')  $assets.zig.MB
Add-Step 'gcc'   'MinGW-Compiler WinLibs (gcc, make, cmake fuer die Hilfswerkzeuge)'          (Tool-Done 'gcc')  $assets.gcc.MB
Add-Step 'uv'    'uv fuer die Python-Skripte (laedt beim ersten Lauf noch ca. 30 MB Python)' (Tool-Done 'uv')   $assets.uv.MB
Add-Step 'node'  'Node.js (kleiner lokaler Server, nur 127.0.0.1)'                           (Tool-Done 'node') $assets.node.MB
Add-Step 'deps'  'zlib 1.3.2 und libpng 1.6.59 (Quellcode mit Pruefsumme, wird selbst gebaut)' (Test-Path (Join-Path $depsDir 'lib\libpng.a')) 3
Add-Step 'src'   "Spiel-Quellcode tripplyons/pokeemerald-wasm @ $($upstreamSha.Substring(0,8)) plus Windows-Patch" (Source-Ready) 55
Add-Step 'shim'  'Hilfsprogramme clang/wasm-ld/make einrichten (wenige Sekunden)'            ((Shim-Done) -and (Tool-Done 'zig') -and (Tool-Done 'gcc')) 0
Add-Step 'build' 'Spiel bauen (make wasm, ca. 5 Minuten)'                                    ((Test-Path $wasmFile) -and -not $Rebuild) 0

$pending = @($steps | Where-Object { -not $_.Done })
Write-Host 'PLAN:'
foreach ($s in $steps) {
  $mark = if ($s.Done) { '[x]' } else { '[ ]' }
  $extra = ''; if (-not $s.Done -and $s.MB -gt 0) { $extra = " (ca. $($s.MB) MB)" }
  Write-Host ("  {0} {1}{2}" -f $mark, $s.Label, $extra)
}
$pendingMB = 0; foreach ($s in $pending) { $pendingMB += [int]$s.MB }
Write-Host "PENDING_MB=$pendingMB"

if (-not $Consent) {
  if ($pending.Count -eq 0) { Write-Host 'SETUP_STATE=READY'; Write-Host 'SETUP_OK: Alles vorhanden.'; exit 0 }
  Write-Host 'SETUP_STATE=PENDING'
  Write-Host 'Nur Plan. Zum Ausfuehren: setup.ps1 -Consent'
  exit 0
}

# ---------- Ausfuehren ----------
function Pending([string]$id) { return [bool](@($pending | Where-Object { $_.Id -eq $id }).Count) }
try {
  New-Item -ItemType Directory -Force $home_ | Out-Null
  # Sperre gegen zwei gleichzeitige Installationen (Windows gibt sie frei, sobald dieser Prozess endet, auch nach einem Absturz)
  try { $script:lockStream = [IO.File]::Open((Join-Path $home_ 'setup.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
  catch { Write-Host 'FEHLER: Eine andere Installation laeuft gerade (setup.lock). Bitte warten, bis sie fertig ist, und dann erneut starten.'; exit 20 }
  if (-not (Test-Path -LiteralPath $homeMarker)) { 'Ordner gehoert dem Plugin pokemon-in-claude. Loeschen ist sicher.' | Set-Content -LiteralPath $homeMarker }
  $dlIds = @(); foreach ($id in 'zig', 'gcc', 'uv', 'node') { if (Pending $id) { $dlIds += $id } }
  $toolIds = @($dlIds)
  if (Pending 'deps') { $dlIds += 'zlib' }
  $needSource = Pending 'src'
  if ($dlIds.Count -gt 0 -or $needSource) { Write-Host '>> Alles Fehlende gleichzeitig laden'; Fetch-All $dlIds $needSource }
  if ($dlIds.Count -gt 0) { Write-Host '>> Entpacken'; Extract-All $dlIds }
  if ((Pending 'shim') -or ($toolIds -contains 'zig') -or ($toolIds -contains 'gcc')) { Write-Host '>> Hilfsprogramme einrichten'; Build-Shims }
  if (Pending 'deps') { Write-Host '>> zlib und libpng bauen'; Build-Deps }
  if ($needSource)    { Write-Host '>> Spiel-Quellcode vorbereiten'; Finish-Source }
  if (Pending 'build') { Write-Host '>> Spiel bauen'; Build-Game }
} catch { Write-Host "FEHLER: $($_.Exception.Message)"; exit 20 }

if (Test-Path $wasmFile) {
  if (Test-Path $dl) { try { Remove-Tree $dl } catch { Write-Host "Hinweis: $dl konnte nicht geloescht werden." } }   # Archive werden nicht mehr gebraucht
  Write-Host ("SETUP_OK: {0:N1} MB" -f ((Get-Item $wasmFile).Length / 1MB)); exit 0
}
Write-Host 'FEHLER: pokeemerald.wasm fehlt nach dem Bau.'; exit 20
