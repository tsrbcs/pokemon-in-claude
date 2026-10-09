import type { EngineInterface, Register } from 'claude-code'

// Mod von pokemon-in-claude. Er zeichnet waehrend Claude arbeitet eine Leiste ueber dem Eingabefeld
// (Laufzeit, ob der Spielserver bereit ist, Schalter fuer den Ping) und bietet zwei Befehle:
//   /pokemon-status        laeuft der Spielserver auf 127.0.0.1:8000?
//   /pokemon-ping on|off   Ping ein- oder ausschalten
//   /pokemon               Spiel einrichten (nach "/pokemon ja") und den Spielserver starten
// Reiner Mod: kein Skill, keine Befehls-Hooks. Der Ping ist die Meldung (Toast) am Zugende; Ton und Taskleiste gibt es nicht mehr.
// Der Ping-Schalter ist die Datei "ping" im Plugin-Ordner des Nutzers (Inhalt "on" oder "off").

const PORT = 8000
type Api = EngineInterface

async function pingPath($: Api): Promise<string | undefined> {
  const own = await $.env.get('POKEMON_IN_CLAUDE_HOME')
  const local = await $.env.get('LOCALAPPDATA')
  const home = own ?? (local === undefined ? undefined : local + '\\pokemon-in-claude')
  return home === undefined ? undefined : home + '\\ping'
}

async function isPingOn($: Api): Promise<boolean> {
  const path = await pingPath($)
  if (path === undefined || !(await $.fs.exists(path))) return false
  return (await $.fs.read(path)).trim() === 'on'
}

async function setPing($: Api, isOn: boolean): Promise<void> {
  const path = await pingPath($)
  if (path !== undefined) await $.fs.write(path, isOn ? 'on' : 'off')
}

async function isServerUp($: Api): Promise<boolean> {
  try {
    const res = await $.http.fetch('http://127.0.0.1:' + PORT + '/build/wasm/pokeemerald.wasm', { method: 'HEAD' })
    return res.ok && (res.headers['content-type'] ?? '').includes('wasm')
  } catch {
    return false
  }
}

const PS = ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File']

function runScript($: Api, name: string, args: string[] = [], timeoutMs = 120000) {
  return $.process.run([...PS, $.plugin.root + '\\scripts\\' + name, ...args], { timeoutMs })
}

let isSetupRunning = false

// Einrichtung im Hintergrund: laedt nur nach ausdruecklichem "/pokemon ja", startet danach den Server
async function runSetup($: Api): Promise<void> {
  isSetupRunning = true
  $.ui.status('Pokemon: richte ein ...')
  try {
    const setup = $.process.spawn({ argv: [...PS, $.plugin.root + '\\scripts\\setup.ps1', '-Consent'] })
    let isOk = false
    let lastLine = ''
    for await (const { text } of setup) {
      if (text.includes('SETUP_OK')) isOk = true
      const line = text.trim().split(/\r?\n/).pop()
      if (line) {
        lastLine = line
        $.ui.status('Pokemon: ' + line)
      }
    }
    if (!isOk) {
      $.ui.toast('Pokemon-Einrichtung fehlgeschlagen: ' + lastLine, { timeoutMs: 15000 })
      return
    }
    const start = await runScript($, 'start.ps1')
    $.ui.toast(
      start.exitCode === 0
        ? 'Pokemon bereit: http://127.0.0.1:' + PORT + '/ im Browser-Bereich oeffnen.'
        : 'Pokemon eingerichtet, Server startet nicht: ' + start.stdout.trim(),
      { timeoutMs: 15000 },
    )
  } finally {
    isSetupRunning = false
    $.ui.status(undefined)
  }
}

export const register: Register = on => {
  let startedAt = 0
  let isWorking = false
  let isUp = false
  let isPing = false
  let tick: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'pokemon', description: 'Pokemon Emerald einrichten und den Spielserver starten (/pokemon ja = Einrichtung erlauben)' })
    await $.command.register({ name: 'pokemon-status', description: 'Zeigt, ob der Pokemon-Spielserver laeuft' })
    await $.command.register({ name: 'pokemon-ping', description: 'Ping ein- oder ausschalten: /pokemon-ping on oder off' })
    return next(e)
  })

  on('command.run', { command: 'pokemon' }, async ($, e) => {
    if (isSetupRunning) return { text: 'Die Einrichtung laeuft schon. Stand: /pokemon-status.' }
    const plan = await runScript($, 'setup.ps1')
    if (plan.exitCode !== 0) return { text: 'Einrichtung nicht moeglich:\n' + plan.stdout.trim() }
    if (plan.stdout.includes('SETUP_STATE=PENDING')) {
      const mb = /PENDING_MB=(\d+)/.exec(plan.stdout)?.[1] ?? '?'
      if (e.args.trim().toLowerCase() !== 'ja') {
        return {
          text:
            (plan.stdout.split('SETUP_STATE')[0] ?? '').trim() +
            '\n\nEs fehlt etwas (' + mb + ' MB Download, keine Admin-Rechte). Erlauben mit: /pokemon ja',
        }
      }
      void runSetup($)
      return { text: 'Einrichtung gestartet (' + mb + ' MB). Fortschritt in der Statuszeile, Ende als Meldung.' }
    }
    const start = await runScript($, 'start.ps1')
    return {
      text:
        start.exitCode === 0
          ? 'Spielserver laeuft: http://127.0.0.1:' + PORT + '/ (im Browser-Bereich oeffnen). Tasten: WASD, Leertaste=A, Q=B, E=Start, Shift=Select. Spielstand sichern: "Download .sav".'
          : 'Spielserver startet nicht:\n' + start.stdout.trim(),
    }
  })

  on('command.run', { command: 'pokemon-status' }, async $ => {
    if (isSetupRunning) return { text: 'Die Einrichtung laeuft noch (siehe Statuszeile).' }
    const isUpNow = await isServerUp($)
    return {
      text: isUpNow
        ? 'Der Spielserver laeuft: http://127.0.0.1:' + PORT + '/ (im Browser-Bereich oeffnen)'
        : 'Der Spielserver laeuft nicht. Starte ihn mit /pokemon.',
    }
  })

  on('command.run', { command: 'pokemon-ping' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg === 'on' || arg === 'off') {
      isPing = arg === 'on'
      await setPing($, isPing)
      return { text: 'Ping ist jetzt ' + (isPing ? 'an' : 'aus') + '.' }
    }
    const isOnNow = await isPingOn($)
    return { text: 'Ping ist ' + (isOnNow ? 'an' : 'aus') + '. Aendern mit /pokemon-ping on oder /pokemon-ping off.' }
  })

  // Beginn eines Zuges von Claude (Zuege von Unteragenten zaehlen nicht)
  on('turn.start', async ($, e, next) => {
    if ((e as { agentId?: string }).agentId === undefined) {
      startedAt = await $.clock.now()
      isWorking = true
      isPing = await isPingOn($)
      isUp = await isServerUp($)
      tick?.cancel()
      tick = $.clock.every(1000, () => $.ui.invalidate('ui.render'))
      $.ui.invalidate('ui.render')
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) {
      tick?.cancel()
      tick = undefined
      isWorking = false
      $.ui.invalidate('ui.render')
      if (!e.isAborted && (await isPingOn($))) {
        $.ui.toast('Claude ist fertig. Zurueck zu Claude.', { timeoutMs: 8000 })
      }
    }
    return next(e)
  })

  // Die Leiste ueber dem Eingabefeld, nur solange Claude arbeitet
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey || !isWorking) return next(e)

    const seconds = Math.max(0, Math.floor(((await $.clock.now()) - startedAt) / 1000))
    const time = Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0')
    const { Box, Button, Text } = $.ui.resolve(e)

    return (
      <Box>
        <Text>
          Pokemon-Pause: Claude arbeitet seit {time} · Spielserver {isUp ? 'bereit' : 'aus (/pokemon)'}{' '}
        </Text>
        <Button
          key="ping"
          label={isPing ? 'Ping: an' : 'Ping: aus'}
          onPress={async () => {
            isPing = !isPing
            await setPing($, isPing)
            $.ui.invalidate('ui.render')
          }}
        />
      </Box>
    )
  })
}
