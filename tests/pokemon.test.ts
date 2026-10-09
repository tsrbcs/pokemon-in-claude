import { expect, test } from 'claude-code/testing'

const wasmOk = { status: 200, ok: true, headers: { 'content-type': 'application/wasm' }, text: '' }
const turn = { answer: 'ok', durationMs: 1000, isAborted: false, turnId: 't1', reason: 'answer' as const }

test('/pokemon-status meldet einen laufenden Spielserver', async ($, on) => {
  on('http.fetch', () => ({ value: wasmOk }))

  const answer = await $.command.run({ command: 'pokemon-status', args: '' })
  expect(answer.text).toContain('Der Spielserver laeuft')
})

test('/pokemon-status meldet, wenn nichts antwortet', async ($, on) => {
  on('http.fetch', () => ({ deny: 'connection refused' }))

  const answer = await $.command.run({ command: 'pokemon-status', args: '' })
  expect(answer.text).toContain('laeuft nicht')
})

test('/pokemon-status erkennt einen fremden Dienst auf dem Port', async ($, on) => {
  on('http.fetch', () => ({ value: { status: 200, ok: true, headers: { 'content-type': 'text/html' }, text: '' } }))

  const answer = await $.command.run({ command: 'pokemon-status', args: '' })
  expect(answer.text).toContain('etwas anderes')
})

test('Meldung am Zugende nur bei eingeschaltetem Ping', async ($, on) => {
  const toasts: string[] = []
  let isPingOn = true
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  on('env.get', (_$, e) => ({ value: e.name === 'POKEMON_IN_CLAUDE_HOME' ? 'C:\\test-home' : undefined }))
  on('fs.exists', () => ({ value: isPingOn }))
  on('ui.toast', (_$, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })

  await $.turn.complete(turn)
  expect(toasts.length).toBe(1)

  isPingOn = false
  await $.turn.complete(turn)
  expect(toasts.length).toBe(1)
})

test('Keine Meldung, wenn der Zug abgebrochen wurde', async ($, on) => {
  const toasts: string[] = []
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  on('env.get', (_$, e) => ({ value: e.name === 'POKEMON_IN_CLAUDE_HOME' ? 'C:\\test-home' : undefined }))
  on('fs.exists', () => ({ value: true }))
  on('ui.toast', (_$, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })

  await $.turn.complete({ ...turn, isAborted: true, reason: 'aborted' })
  expect(toasts.length).toBe(0)
})
