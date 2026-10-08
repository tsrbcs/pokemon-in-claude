# pokemon-in-claude

Spiele **Pokémon Emerald** direkt im Browser-Bereich von Claude, während Claude arbeitet. Sobald Claude fertig ist oder dich braucht, holt dich ein Ping zurück: Ton, blinkende Taskleiste und eine Meldung mit einem kleinen Tipp.

Läuft ohne Emulator: Das Spiel ist der Quellcode der Pokémon-Emerald-Dekompilation, übersetzt zu WebAssembly ([tripplyons/pokeemerald-wasm](https://github.com/tripplyons/pokeemerald-wasm)). Du brauchst keine ROM.

## Installieren (2 Schritte)

1. In Claude Code:
   ```
   /plugin marketplace add tsrbcs/pokemon-in-claude
   /plugin install pokemon-in-claude@pokemon-in-claude
   ```
2. Dann einmal:
   ```
   /pokemon-in-claude:pokemon
   ```
   Claude zeigt dir, was noch fehlt und wie groß es ist, und fragt **einmal** um Erlaubnis. Danach richtet es alles selbst ein und öffnet das Spiel im Claude-Browser.

Der Ping ist standardmäßig aus. Zum Einschalten siehe „Ping einschalten“.

## Voraussetzungen

- Windows 10 oder 11
- [Git for Windows](https://git-scm.com/download/win)
- Beim ersten Einrichten rund 1 GB Download und etwa 15 bis 25 Minuten. Windows fragt einmal nach Administratorrechten (für LLVM). Klicke dann auf „Ja“.

## Was heruntergeladen wird

Nichts, bevor du zustimmst. Das Plugin selbst enthält keine Nintendo-Dateien und kein Spiel, nur Skripte und einen kleinen Windows-Patch.

| Was | Größe | Zweck |
|---|---|---|
| LLVM (winget) | ca. 610 MB | Compiler `clang` und `wasm-ld` (Admin-Abfrage) |
| WinLibs MinGW (winget) | ca. 261 MB | `gcc`, `g++`, `make`, `cmake` für die Hilfswerkzeuge |
| uv (winget) | ca. 17 MB | startet die Python-Skripte, lädt beim ersten Lauf ca. 30 MB Python |
| Node.js (winget), falls nicht vorhanden | ca. 30 MB | kleiner lokaler Server (nur `127.0.0.1`) |
| zlib und libpng (Quellcode) | ca. 3 MB | mit festen SHA256-Prüfsummen, wird lokal gebaut |
| Spiel-Quellcode `tripplyons/pokeemerald-wasm` | ca. 55 MB | fester Stand, Commit `fd83f5b6` |

Alles landet unter `%LOCALAPPDATA%\pokemon-in-claude\`.

## Sicherheit

- Der Spielserver lauscht nur auf `127.0.0.1:8000` und ist im Netzwerk nicht erreichbar.
- Der Tracking-Code (Google Tag Manager) des Spiels wird per Patch entfernt.
- Downloads sind an Prüfsummen und feste Commit-Stände gebunden.
- Der Bau führt Python-Skripte und Hilfsprogramme aus dem Upstream-Projekt aus. Es ist ein Vertrauensvorschuss in dieses Projekt, wie bei jedem selbst gebauten Programm.

## Spielen

Der Browser-Bereich muss **sichtbar** sein, sonst bremst der Browser das Spiel auf etwa 6 Bilder pro Sekunde.

Tasten: Pfeile, `Z` = A, `X` = B, `Enter` = Start, `Shift` = Select.

Der Spielstand liegt im Browser unter `127.0.0.1:8000`. Sichere ihn mit „Download .sav“, ein Browserwechsel oder ein gelöschter Browserspeicher löscht ihn sonst.

## Eigene Tipps im Ping

Lege die Datei `%LOCALAPPDATA%\pokemon-in-claude\nudges.txt` an, eine Zeile pro Tipp, zum Beispiel:

```
2 Min: Titel für das nächste Video aufschreiben.
2 Min: Eine Rechnung schreiben.
```

## Ping einschalten

Lege eine leere Datei `%LOCALAPPDATA%\pokemon-in-claude\ping-on` an. Solange sie existiert, gibt es Ton, Meldung und Blinken. Löschst du die Datei, ist der Ping wieder aus. Alternativ das Plugin abschalten: `claude plugin disable pokemon-in-claude@pokemon-in-claude`.

## Deinstallieren

```
/plugin uninstall pokemon-in-claude@pokemon-in-claude
```

Danach den Ordner `%LOCALAPPDATA%\pokemon-in-claude` löschen. Die per winget installierten Programme bleiben bestehen und lassen sich mit `winget uninstall` entfernen.

## Rechtliches

Inoffizielles Fan-Projekt, nicht von Nintendo, Game Freak oder The Pokémon Company. Pokémon und Pokémon Emerald sind Marken ihrer Inhaber. Dieses Repository enthält keinen Nintendo-Inhalt. Das Einrichten lädt das öffentliche Projekt `tripplyons/pokeemerald-wasm` auf deinen Rechner, das auf der Dekompilation `pret/pokeemerald` beruht. Nutze es für private, nicht kommerzielle Zwecke und beachte die Lizenzen und Rechte der Projekte. Die MIT-Lizenz in `LICENSE` gilt nur für die Skripte, die Konfiguration und die Dokumentation dieses Repositories, nicht für Pokémon-Inhalte und nicht für das heruntergeladene Projekt `tripplyons/pokeemerald-wasm`.

## Fehlersuche

- Logs: `%LOCALAPPDATA%\pokemon-in-claude\logs\` (`setup.log`, `build.log`, `server.err.log`).
- Kein Ping: Prüfe, ob in `%TEMP%` die Datei `pokemon-ping.last` entsteht, und starte Claude einmal neu, damit der Hook geladen wird.
- Port 8000 belegt: Beende das andere Programm, der Port ist fest, damit dein Spielstand erhalten bleibt.
