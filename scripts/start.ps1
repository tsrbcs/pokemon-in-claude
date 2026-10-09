# start.ps1 - startet den lokalen Spiele-Server (nur 127.0.0.1:8000), falls er nicht schon laeuft.
# Fester Port 8000 ist wichtig: Der Spielstand liegt im Browser unter genau dieser Adresse.
param([int]$Port = 8000)

$home_ = if ($env:POKEMON_IN_CLAUDE_HOME) { $env:POKEMON_IN_CLAUDE_HOME } else { Join-Path $env:LOCALAPPDATA 'pokemon-in-claude' }
$repo  = Join-Path $home_ 'src\pokeemerald-wasm'
$wasm  = Join-Path $repo 'build\wasm\pokeemerald.wasm'
$logs  = Join-Path $home_ 'logs'
$url   = "http://127.0.0.1:$Port/"

if (-not (Test-Path $wasm)) { Write-Host "NOT_BUILT: Noch nicht eingerichtet. Zuerst /pokemon bzw. setup.ps1 -Consent ausfuehren."; exit 1 }
$ownNode = Join-Path $home_ 'node\node.exe'
$node = if (Test-Path $ownNode) { $ownNode } else { (Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
if ($node -and $node -ne $ownNode) { $v = (& $node --version 2>$null | Out-String).Trim(); if (-not ($v -match '^v(\d+)\.' -and [int]$Matches[1] -ge 18)) { $node = $null } }
if (-not $node) { Write-Host "NODE_MISSING: Node.js ab Version 18 fehlt. Bitte /pokemon ausfuehren, das richtet es ein."; exit 4 }

$c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($c) {
  # Ist es wirklich unser Spielserver? Er liefert die .wasm-Datei mit passendem Typ aus.
  $ours = $false
  try { $r = Invoke-WebRequest -Uri ($url + 'build/wasm/pokeemerald.wasm') -Method Head -UseBasicParsing -TimeoutSec 4; $ours = ($r.StatusCode -eq 200 -and ([string]$r.Headers['Content-Type']) -like '*wasm*') } catch {}
  if (-not $ours) { $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue; Write-Host "PORT_BUSY: Port $Port ist von '$($p.ProcessName)' belegt und antwortet nicht wie das Spiel."; exit 2 }
  Write-Host "Server laeuft bereits (PID $($c.OwningProcess))."
} else {
  New-Item -ItemType Directory -Force $logs | Out-Null
  # Ueber WMI starten: Der Server erbt dann keine Ausgabe-Leitung des Aufrufers (sonst blockiert ein
  # wartender Aufrufer, z. B. ein Werkzeug, das auf das Ende der Ausgabe wartet) und laeuft unabhaengig weiter.
  $line = 'set PORT={0}&& "{1}" web/server.mjs > "{2}" 2> "{3}"' -f $Port, $node, (Join-Path $logs 'server.log'), (Join-Path $logs 'server.err.log')
  $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = ('cmd.exe /d /s /c "{0}"' -f $line); CurrentDirectory = $repo }
  if ($r.ReturnValue -ne 0) { Write-Host "START_FAILED: WMI-Fehler $($r.ReturnValue)"; exit 3 }
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) { break }
  }
  if (-not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)) { Write-Host "START_FAILED: Siehe $logs\server.err.log"; exit 3 }
  Write-Host "Server gestartet."
}
Write-Host "URL: $url"
