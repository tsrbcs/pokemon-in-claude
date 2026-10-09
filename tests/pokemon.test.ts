import { expect, mock, test } from 'claude-code/testing'

const wasmOk = { status: 200, ok: true, headers: { 'content-type': 'application/wasm' }, text: '' }
const turn = { answer: 'ok', durationMs: 1000, isAborted: false, turnId: 't1', reason: 'answer' as const }

test('/pokemon-status meldet einen laufenden Spielserver', async ($, on) => {
  on('http.fetch', () => ({ value: wasmOk }))

  const answer = await $.command.run({ command: 'pokemon-status', args: '' })
  expect(answer.text).toContain('Der Spielserver laeuft:')
})

test('/pokemon-status meldet, wenn nichts antwortet', async ($, on) => {
  on('http.fetch', () => ({ deny: 'connection refused' }))

  const answer = await $.command.run({ command: 'pokemon-status', args: '' })
  expect(answer.text).toContain('laeuft nicht')
})

test('/pokemon-status erkennt einen fremden Dienst auf dem Port', async ($, on) => {
  on('http.fetch', () => ({ value: { status: 200, ok: true, headers: { 'content-type': 'text/html' }, text: '' } }))

  const answer = await $.command.run({ command: 'pokemon-status', args: '' })
  expect(answer.text).toContain('laeuft nicht')
})

test('/pokemon-ping on schreibt "on" in die Datei ping', async ($, on) => {
  const written: { path: string; text: string }[] = []
  on('env.get', (_$, e) => ({ value: e.name === 'POKEMON_IN_CLAUDE_HOME' ? 'C:\\test-home' : undefined }))
  on('fs.write', (_$, e) => {
    written.push({ path: e.path, text: e.text })
    return { value: undefined }
  })

  const answer = await $.command.run({ command: 'pokemon-ping', args: 'on' })
  expect(answer.text).toContain('jetzt an')
  expect(written.length).toBe(1)
  expect(written[0].path).toBe('C:\\test-home\\ping')
  expect(written[0].text).toBe('on')
})

test('/pokemon-ping ohne Argument nennt den Stand', async ($, on) => {
  on('env.get', (_$, e) => ({ value: e.name === 'POKEMON_IN_CLAUDE_HOME' ? 'C:\\test-home' : undefined }))
  on('fs.exists', () => ({ value: true }))
  on('fs.read', () => ({ value: 'off\n' }))

  const answer = await $.command.run({ command: 'pokemon-ping', args: '' })
  expect(answer.text).toContain('Ping ist aus')
})

test('Meldung am Zugende nur bei eingeschaltetem Ping', async ($, on) => {
  const toasts: string[] = []
  let content = 'on'
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  on('env.get', (_$, e) => ({ value: e.name === 'POKEMON_IN_CLAUDE_HOME' ? 'C:\\test-home' : undefined }))
  on('fs.exists', () => ({ value: true }))
  on('fs.read', () => ({ value: content }))
  on('ui.toast', (_$, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })

  await $.turn.complete(turn)
  expect(toasts.length).toBe(1)

  content = 'off'
  await $.turn.complete(turn)
  expect(toasts.length).toBe(1)
})

test('Keine Meldung bei abgebrochenem Zug und bei Unteragenten', async ($, on) => {
  const toasts: string[] = []
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  on('env.get', (_$, e) => ({ value: e.name === 'POKEMON_IN_CLAUDE_HOME' ? 'C:\\test-home' : undefined }))
  on('fs.exists', () => ({ value: true }))
  on('fs.read', () => ({ value: 'on' }))
  on('ui.toast', (_$, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })

  await $.turn.complete({ ...turn, isAborted: true, reason: 'aborted' })
  await $.turn.complete({ ...turn, agentId: 'sub-1' })
  expect(toasts.length).toBe(0)
})

// Was Claude Code der Leiste über dem Eingabefeld übergibt, abgesehen vom Programm
const BAND = {
  plugin: 'pokemon-in-claude',
  component: 'AbovePrompt',
  requestId: 'above-prompt',
  viewport: { columns: 100, rows: 30 },
  props: { hasSurvey: false, isWorking: true, maxRows: 5, bodyColumns: 90, scroll: { offset: 0, bodyRows: 4 }, view: {} },
} as const

function stubBand(on: Parameters<Parameters<typeof test>[1]>[1], file: { content: string }) {
  on('env.get', (_$, e) => ({ value: e.name === 'POKEMON_IN_CLAUDE_HOME' ? 'C:\\test-home' : undefined }))
  on('fs.exists', () => ({ value: true }))
  on('fs.read', () => ({ value: file.content }))
  on('fs.write', (_$, e) => {
    file.content = e.text
    return { value: undefined }
  })
  on('http.fetch', () => ({ value: wasmOk }))
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['drawn by Claude Code'] }))
}

test('Leiste zeigt Laufzeit und Spielserver, solange Claude arbeitet', async ($, on) => {
  const clock = mock.clock(on)
  stubBand(on, { content: 'off' })

  await $.turn.start({ text: 'hallo', turnId: 't1' })
  await clock.advance(65000)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect(await ui.find({ type: 'Text', text: /Claude arbeitet seit 1:0\d/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Spielserver bereit/ })).toBeDefined()
    await ui.unmount()
  }
})

test('Der Knopf in der Leiste schaltet den Ping um', async ($, on) => {
  const clock = mock.clock(on)
  const file = { content: 'off' }
  stubBand(on, file)

  await $.turn.start({ text: 'hallo', turnId: 't1' })
  await clock.advance(1000)

  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect(await ui.find({ key: 'ping', type: 'Button' })).toBeDefined()
  await ui.press({ key: 'ping' })
  expect(file.content).toBe('on')
  await ui.press({ key: 'ping' })
  expect(file.content).toBe('off')
  await ui.unmount()
})

test('Ohne laufenden Zug zeichnet die Leiste nichts Eigenes', async ($, on) => {
  stubBand(on, { content: 'off' })

  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /Claude arbeitet/ })).toBeUndefined()
  await ui.unmount()
})

const done = (stdout: string, exitCode = 0) => ({ exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false })

test('/pokemon ohne "ja" zeigt den Plan und laedt nichts', async ($, on) => {
  const calls: string[][] = []
  on('process.run', (_$, e) => {
    calls.push([...e.argv])
    return { value: done('PLAN:\n  [ ] Spiel-Quellcode\nPENDING_MB=55\nSETUP_STATE=PENDING\n') }
  })

  const answer = await $.command.run({ command: 'pokemon', args: '' })
  expect(answer.text).toContain('/pokemon ja')
  expect(answer.text).toContain('55 MB')
  expect(calls.length).toBe(1)
  expect(calls[0].includes('-Consent')).toBe(false)
})

test('/pokemon startet den Spielserver, wenn alles eingerichtet ist', async ($, on) => {
  on('process.run', (_$, e) =>
    ({ value: e.argv.some(a => a.endsWith('setup.ps1')) ? done('SETUP_STATE=READY\nSETUP_OK: Alles vorhanden.\n') : done('Server gestartet.\nURL: http://127.0.0.1:8000/\n') }),
  )

  const answer = await $.command.run({ command: 'pokemon', args: '' })
  expect(answer.text).toContain('Spielserver laeuft: http://127.0.0.1:8000/')
})
