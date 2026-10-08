# ping.ps1 - holt dich aus Pokemon zurueck, wenn Claude dich braucht (Hooks: Notification, Stop).
# Ton + Taskleiste blinken + Toast mit einem kleinen Schritt fuer dein Ziel. Beendet immer mit Exit 0.
# Eigene Tipps: Datei %LOCALAPPDATA%\pokemon-in-claude\nudges.txt (eine Zeile pro Tipp).
param([string]$EventName = 'Stop', [switch]$Test)
# AUSSCHALTER: Existiert die Datei no-ping im Ordner pokemon-in-claude, passiert nichts (kein Ton, kein Toast, kein Blinken).
$pokeHome_ = if ($env:POKEMON_IN_CLAUDE_HOME) { $env:POKEMON_IN_CLAUDE_HOME } else { Join-Path $env:LOCALAPPDATA 'pokemon-in-claude' }
if (Test-Path -LiteralPath (Join-Path $pokeHome_ 'no-ping')) { exit 0 }

$ErrorActionPreference = 'SilentlyContinue'

# Hook-Eingabe (JSON auf stdin) lesen, falls vorhanden
$msg = ''
if (-not $Test) {
  try {
    $raw = [Console]::In.ReadToEnd()
    if ($raw) { $j = $raw | ConvertFrom-Json; if ($j.message) { $msg = [string]$j.message } }
  } catch {}
}

# Doppelte Pings (Notification + Stop kurz hintereinander) unterdruecken
$stamp = Join-Path $env:TEMP 'pokemon-ping.last'
if (-not $Test -and (Test-Path $stamp)) {
  $last = [datetime]::Parse((Get-Content $stamp -Raw).Trim())
  if (((Get-Date) - $last).TotalSeconds -lt 15) { exit 0 }
}
(Get-Date).ToString('o') | Set-Content $stamp

# Text
if ($EventName -eq 'Notification') { $title = 'Claude braucht dich'; $body = if ($msg) { $msg } else { 'Eine Entscheidung wartet auf dich.' } }
else                               { $title = 'Claude ist fertig';   $body = 'Zurueck zu Claude. Dein Spielstand bleibt im Browser erhalten.' }

$home_ = if ($env:POKEMON_IN_CLAUDE_HOME) { $env:POKEMON_IN_CLAUDE_HOME } else { Join-Path $env:LOCALAPPDATA 'pokemon-in-claude' }
$steps = @(
  '2 Min: Schreib auf, was dein Ziel heute am meisten voranbringt.',
  '2 Min: Eine kleine Aufgabe fuer dein Ziel erledigen.',
  '2 Min: Den naechsten Schritt fuer dein Ziel in einem Satz notieren.',
  '2 Min: Eine Sache vom Tisch raeumen, die dich bremst.'
)
$file = Join-Path $home_ 'nudges.txt'
if (Test-Path $file) { $own = @(Get-Content $file -Encoding UTF8 | Where-Object { $_.Trim() }); if ($own.Count -gt 0) { $steps = $own } }
$nudge = 'Tipp: ' + ($steps | Get-Random)

# 1) Ton
try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}

# 2) Claude-Fenster in der Taskleiste blinken lassen
try {
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class PokePingFlash {
  [StructLayout(LayoutKind.Sequential)] public struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }
  [DllImport("user32.dll")] public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);
  public static void Flash(IntPtr h) { FLASHWINFO f = new FLASHWINFO(); f.cbSize = (uint)Marshal.SizeOf(f); f.hwnd = h; f.dwFlags = 3 | 12; f.uCount = 5; f.dwTimeout = 0; FlashWindowEx(ref f); }
}
"@
  $w = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and ($_.ProcessName -match '^claude$' -or $_.MainWindowTitle -match 'Claude') } | Select-Object -First 1
  if ($w) { [PokePingFlash]::Flash($w.MainWindowHandle) }
} catch {}

# 3) Toast
try {
  [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
  $esc = { param($s) [System.Security.SecurityElement]::Escape($s) }
  $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
  $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$(& $esc $title)</text><text>$(& $esc $body)</text><text>$(& $esc $nudge)</text></binding></visual></toast>")
  $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
  $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
} catch {}

exit 0
