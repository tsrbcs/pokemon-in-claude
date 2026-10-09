import type { EngineInterface, Register } from 'claude-code'

// Mod von pokemon-in-claude. Er zeichnet waehrend Claude arbeitet eine Leiste ueber dem Eingabefeld
// (Laufzeit, ob der Spielserver bereit ist, Schalter fuer den Ping) und bietet zwei Befehle:
//   /pokemon-status        laeuft der Spielserver auf 127.0.0.1:8000?
//   /pokemon-ping on|off   Ping ein- oder ausschalten
// Ton, Taskleiste und Windows-Meldung kommen weiter von scripts/ping.ps1 (der Mod spielt unter Windows keinen Ton).
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

export const register: Register = on => {
  let startedAt = 0
  let isWorking = false
  let isUp = false
  let isPing = false
  let tick: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'pokemon-status', description: 'Zeigt, ob der Pokemon-Spielserver laeuft' })
    await $.command.register({ name: 'pokemon-ping', description: 'Ping ein- oder ausschalten: /pokemon-ping on oder off' })
    return next(e)
  })

  on('command.run', { command: 'pokemon-status' }, async $ => {
    const isUpNow = await isServerUp($)
    return {
      text: isUpNow
        ? 'Der Spielserver laeuft: http://127.0.0.1:' + PORT + '/ (im Browser-Bereich oeffnen)'
        : 'Der Spielserver laeuft nicht. Starte ihn mit /pokemon-in-claude:pokemon.',
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
    if (e.agentId === undefined) {
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
          Pokemon-Pause: Claude arbeitet seit {time} · Spielserver {isUp ? 'bereit' : 'aus (/pokemon-in-claude:pokemon)'}{' '}
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
