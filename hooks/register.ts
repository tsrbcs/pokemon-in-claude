import type { Register } from 'claude-code'

// Mod-Teil von pokemon-in-claude. Er ergaenzt die Shell-Hooks (ping.ps1: Ton, Taskleiste, Windows-Meldung):
//  - zeigt in Claude Code selbst eine Meldung, wenn ein Zug fertig ist (nur bei eingeschaltetem Ping),
//  - bietet /pokemon-status: laeuft der Spielserver auf 127.0.0.1:8000?
// Bewusst klein: Ton und Taskleiste gehen ueber ping.ps1, denn $.audio spielt unter Windows nichts.

const PORT = 8000

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'pokemon-status',
      description: 'Zeigt, ob der Pokemon-Spielserver laeuft',
    })
    return next(e)
  })

  on('command.run', { command: 'pokemon-status' }, async $ => {
    try {
      const res = await $.http.fetch('http://127.0.0.1:' + PORT + '/build/wasm/pokeemerald.wasm', { method: 'HEAD' })
      const isGame = res.ok && (res.headers['content-type'] ?? '').includes('wasm')
      return {
        text: isGame
          ? 'Der Spielserver laeuft: http://127.0.0.1:' + PORT + '/ (im Browser-Bereich oeffnen)'
          : 'Auf Port ' + PORT + ' antwortet etwas anderes als das Spiel.',
      }
    } catch {
      return { text: 'Der Spielserver laeuft nicht. Starte ihn mit /pokemon-in-claude:pokemon.' }
    }
  })

  on('turn.complete', async ($, e, next) => {
    // Der Ping ist an, wenn die Datei ping-on im Plugin-Ordner des Nutzers liegt (siehe README).
    const own = await $.env.get('POKEMON_IN_CLAUDE_HOME')
    const local = await $.env.get('LOCALAPPDATA')
    const home = own ?? (local === undefined ? undefined : local + '\\pokemon-in-claude')
    const isOn = home !== undefined && (await $.fs.exists(home + '\\ping-on'))
    if (isOn && !e.isAborted) {
      $.ui.toast('Claude ist fertig. Zurueck zu Claude.', { timeoutMs: 8000 })
    }
    return next(e)
  })
}
