# pokemon-in-claude

Spiele **Pokémon Emerald** direkt im Browser-Bereich von Claude, während Claude arbeitet. Sobald Claude fertig ist, holt dich auf Wunsch eine Meldung zurück.

Das Ganze ist ein reiner **Mod** (ab Claude Code 2.1.287): kein Skill, keine Befehls-Hooks, nur `hooks/register.tsx`.

Läuft ohne Emulator: Das Spiel ist der Quellcode der Pokémon-Emerald-Dekompilation, übersetzt zu WebAssembly ([tripplyons/pokeemerald-wasm](https://github.com/tripplyons/pokeemerald-wasm)). Du brauchst keine ROM.

## Installieren (2 Schritte)

1. In Claude Code:
   ```
   /plugin marketplace add tsrbcs/pokemon-in-claude
   /plugin install pokemon-in-claude@pokemon-in-claude
   ```
2. Dann einmal:
   ```
   /pokemon
   ```
   Der Mod zeigt dir, was noch fehlt und wie groß es ist. Mit `/pokemon ja` erlaubst du die Einrichtung (**einmal**). Danach richtet er alles selbst ein und startet den Spielserver. Öffne dann `http://127.0.0.1:8000/` im Browser-Bereich von Claude.

Die Meldung am Zugende ist standardmäßig aus. Zum Einschalten siehe „Meldung einschalten“.

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

Tasten: `W` `A` `S` `D` = Steuerkreuz, `Leertaste` = A, `Q` = B, `E` = Start, `Shift` = Select. Die alten Tasten gehen weiter: Pfeile, `Z` = A, `X` = B, `Enter` = Start.

Geschwindigkeit: `1` = 1x, `2` = 2x, `3` = 3x. Auf der Oberfläche gibt es **Quick Save** und **Quick Load**: Sie sichern und laden den ganzen Spielzustand (nur im Arbeitsspeicher, weg nach dem Neuladen der Seite). Der normale Spielstand (Speichern im Spiel) bleibt dabei unberührt.

Einen Ton gibt es nicht: Der Port baut keinen Audio-Mixer ein (`SoundMain` ist leer), das Spiel ist stumm.

Der Spielstand liegt im Browser unter `127.0.0.1:8000`. Sichere ihn mit „Download .sav“, ein Browserwechsel oder ein gelöschter Browserspeicher löscht ihn sonst.

## Meldung einschalten

Tippe `/pokemon-ping on` (ausschalten: `/pokemon-ping off`). Solange sie an ist, zeigt Claude Code am Zugende eine Meldung. Während Claude arbeitet, zeigt die Leiste über dem Eingabefeld außerdem den Schalter „Ping: an/aus“. Der Schalter ist die Textdatei `%LOCALAPPDATA%\pokemon-in-claude\ping` mit dem Inhalt `on` oder `off`.

## Was der Mod tut

Der Mod (`hooks/register.tsx`) läuft in Claude Code selbst, mit deinen Rechten, so wie jedes Plugin mit Code. Du siehst vorher, was er tut: `claude plugin validate <Plugin-Ordner>` listet seine Hooks und Aufrufe. Er startet nur die Skripte aus `scripts/` (Einrichten und Spielserver), liest und schreibt die Datei `ping` im Plugin-Ordner, liest `LOCALAPPDATA` und `POKEMON_IN_CLAUDE_HOME` und fragt `127.0.0.1:8000` an.

- **`/pokemon`** zeigt den Plan; mit `/pokemon ja` richtet er das Spiel ein und startet den Spielserver.
- **Leiste über dem Eingabefeld:** Solange Claude arbeitet, zeigt sie die Laufzeit, ob der Spielserver bereit ist, und den Schalter „Ping: an/aus“.
- **`/pokemon-status`** zeigt, ob der Spielserver läuft.
- **`/pokemon-ping on|off`** schaltet die Meldung ein oder aus.
- **Meldung am Zugende:** Bei eingeschaltetem Ping zeigt Claude Code eine Meldung, wenn Claude fertig ist.

Ton und blinkende Taskleiste gibt es nicht mehr. Tests: `claude plugin test` im Plugin-Ordner.

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
- Keine Antwort auf `/pokemon`: Der Mod wird erst nach `/reload-plugins` oder einem Neustart geladen.
- Port 8000 belegt: Beende das andere Programm, der Port ist fest, damit dein Spielstand erhalten bleibt.
