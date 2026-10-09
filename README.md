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
- Beim ersten Einrichten rund 310 MB Download und etwa 7 bis 15 Minuten (gemessen: 6,9 Minuten bei schneller Leitung, davon der Bau etwa 5 Minuten). Es sind **keine Administratorrechte** nötig, und Windows zeigt keine Abfrage.
- Plattenplatz: rund 1,6 GB unter `%LOCALAPPDATA%\pokemon-in-claude\` (die Programme entpacken sich größer, als sie zu laden sind).

## Was heruntergeladen wird

Nichts, bevor du zustimmst. Das Plugin selbst enthält keine Nintendo-Dateien und kein Spiel, nur Skripte und einen kleinen Windows-Patch.

| Was | Größe | Zweck |
|---|---|---|
| Zig 0.17.0 | ca. 96 MB | Compiler (`clang`) und Linker (`wasm-ld`) für WebAssembly |
| WinLibs MinGW (7z) | ca. 105 MB | `gcc`, `g++`, `make`, `cmake` für die Hilfswerkzeuge |
| uv | ca. 17 MB | startet die Python-Skripte, lädt beim ersten Lauf ca. 30 MB Python |
| Node.js (portabel), falls keins ab Version 18 vorhanden ist | ca. 36 MB | kleiner lokaler Server (nur `127.0.0.1`) |
| zlib und libpng (Quellcode) | ca. 3 MB | mit festen SHA256-Prüfsummen, wird lokal gebaut |
| Spiel-Quellcode `tripplyons/pokeemerald-wasm` | ca. 55 MB | fester Stand, Commit `fd83f5b6` |

Alles landet unter `%LOCALAPPDATA%\pokemon-in-claude\`. Es wird nichts außerhalb dieses Ordners installiert (kein PATH-Eintrag, keine Registry, keine Admin-Rechte). Die Downloads laufen alle gleichzeitig über HTTPS, jede Datei wird vor dem Entpacken gegen ihre feste SHA256-Prüfsumme geprüft. Bricht etwas ab, setzt ein erneutes `/pokemon` dort fort, wo es stand.

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
2 Min: Den nächsten Schritt für mein Projekt aufschreiben.
2 Min: Eine offene Mail beantworten.
```

## Ping einschalten

Lege eine leere Datei `%LOCALAPPDATA%\pokemon-in-claude\ping-on` an. Solange sie existiert, gibt es Ton, Meldung und Blinken. Löschst du die Datei, ist der Ping wieder aus. Alternativ das Plugin abschalten: `claude plugin disable pokemon-in-claude@pokemon-in-claude`.

## Mod (ab Claude Code 2.1.287)

Das Plugin enthält einen kleinen Mod (`hooks/register.ts`). Er läuft in Claude Code selbst, mit deinen Rechten, so wie jedes Plugin mit Code. Du siehst vorher, was er tut: `claude plugin validate <Plugin-Ordner>` listet seine Hooks und Aufrufe (er liest nur `ping-on`, `LOCALAPPDATA` und `POKEMON_IN_CLAUDE_HOME` und fragt `127.0.0.1:8000` an).

- **`/pokemon-status`** zeigt, ob der Spielserver läuft.
- **Meldung am Zugende:** Bei eingeschaltetem Ping zeigt Claude Code zusätzlich eine Meldung, wenn ein Zug fertig ist.

Ton, blinkende Taskleiste und Windows-Meldung kommen weiter von `ping.ps1`, denn die Mod-Schnittstelle spielt unter Windows keinen Ton ab. Tests: `claude plugin test` im Plugin-Ordner.

## Deinstallieren

```
/plugin uninstall pokemon-in-claude@pokemon-in-claude
/plugin marketplace remove pokemon-in-claude
```

Danach den Ordner `%LOCALAPPDATA%\pokemon-in-claude` löschen. Mehr gibt es nicht zu entfernen, denn außerhalb dieses Ordners wurde nichts installiert.

## Rechtliches

Inoffizielles Fan-Projekt, nicht von Nintendo, Game Freak oder The Pokémon Company. Pokémon und Pokémon Emerald sind Marken ihrer Inhaber. Dieses Repository enthält keinen Nintendo-Inhalt. Das Einrichten lädt das öffentliche Projekt `tripplyons/pokeemerald-wasm` auf deinen Rechner, das auf der Dekompilation `pret/pokeemerald` beruht. Nutze es für private, nicht kommerzielle Zwecke und beachte die Lizenzen und Rechte der Projekte. Die MIT-Lizenz in `LICENSE` gilt nur für die Skripte, die Konfiguration und die Dokumentation dieses Repositories, nicht für Pokémon-Inhalte und nicht für das heruntergeladene Projekt `tripplyons/pokeemerald-wasm`.

## Fehlersuche

- Logs: `%LOCALAPPDATA%\pokemon-in-claude\logs\` (`setup.log`, `build.log`, `server.err.log`).
- Kein Ping: Prüfe, ob in `%TEMP%` die Datei `pokemon-ping.last` entsteht, und starte Claude einmal neu, damit der Hook geladen wird.
- Port 8000 belegt: Beende das andere Programm, der Port ist fest, damit dein Spielstand erhalten bleibt.
