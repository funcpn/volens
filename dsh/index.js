/**
 * volens on DeepSeek Harness: the sync mechanism as an in-process plugin.
 *
 * This is the second implementation of volens' sync semantics. The first,
 * `hooks/volens-sync.sh`, runs as a child process and speaks a JSON contract on
 * stdout; Claude Code and Codex call it that way. DSH loads plugins into its own
 * process instead, so the two channels a hook process uses do not exist here: a
 * listener returns a `PreStepDecision` rather than printing `additionalContext`,
 * and there is no `systemMessage` channel at all. The three branches, the cursor
 * and the newline anchor are the same specification in both implementations, and
 * the shell script stays the reference — an inconsistency between the two is a
 * defect, not a harness difference.
 *
 * Registered on one event only:
 *
 *   agent/pre-step, gated on step === 1
 *
 * That is the turn head, the equivalent of Codex's `UserPromptSubmit`. The gate is
 * load-bearing: `agent/pre-step` fires once per model step, so a turn containing
 * five tool calls would otherwise run the check five times. Two candidates were
 * rejected (decision 33): `agent/created`, because a session-start check and the
 * first turn's check would see the same state and inject the same delta twice —
 * and dropping it also removed the need for remembered dedup state — and
 * `agent/turn-stopping`, whose only output is a forced extra model step and which
 * would therefore cost one model call per delta plus a loop guard.
 *
 * Switch semantics, one branch per run:
 *   M < N          the log was rewritten -> reset the cursor, inject a full rebuild
 *   design >= log  DESIGN is already current -> fast-forward the cursor, silent
 *   N < M          new log lines -> inject the exact delta N+1..M, cursor untouched
 *
 * M is the log's **newline count** — the number of `\n` characters, which is what
 * the shell implementation's `wc -l` measures, never the number of segments the
 * file splits into. The two differ by one whenever the last line lacks a trailing
 * newline (decision 32).
 *
 * The whole check is synchronous. Node yields only at an `await`, so a single
 * synchronous read-decide-write block cannot be interleaved by another agent
 * working the same project. That is the only reason no lock is needed for the
 * cursor; introducing an `await` between the read and the write would break it.
 *
 * @module volens-dsh
 */

import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { createUserMessage } from '@deepseek-ai/dsh-llm'

/** Cordis plugin name, used by loader diagnostics and as the message source. */
export const name = 'volens'

/** Two or three letters, then up to three subtags: `zh`, `zh-CN`, `zh-Hans-CN`. */
const LANGUAGE_TAG = /^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8}){0,3}$/

/**
 * Read a language tag from a pin file, or `undefined`.
 *
 * The pin is the one project-controlled string that reaches the injected
 * instruction, so it is validated rather than embedded as found. `trim()` removes
 * a no-break space, unlike the shell's `tr -d '[:space:]'`, but the shape check is
 * what rejects a sentence (decision 31).
 *
 * @param {string} file - candidate pin path.
 * @returns {string | undefined} the tag, or undefined when absent or not a tag.
 */
function langTag(file) {
  if (!existsSync(file)) return undefined
  const value = readFileSync(file, 'utf8').trim()
  return LANGUAGE_TAG.test(value) ? value : undefined
}

/**
 * Resolve both languages.
 *
 * Communication (the notice) follows the machine's user-level preference; content
 * (what DESIGN.md is written in) follows the project's committed pin, then that
 * same preference. A pin that exists but holds no tag is ignored, and the fact is
 * remembered so the next notice can say which language is actually in force
 * (decisions 7, 25, 31).
 *
 * @param {string} project - project root.
 * @returns {{ ui: string, doc: string, pinIgnored: boolean }} the resolved pair.
 */
function resolveLanguages(project) {
  const userLevel = join(process.env.XDG_CONFIG_HOME || join(homedir(), '.config'), 'volens', 'lang')
  const ui = langTag(userLevel) ?? 'en'

  const pin = join(project, '.volens', 'lang')
  const legacyPin = join(project, '.claude', 'volens.lang')
  const pinFile = existsSync(pin) ? pin : existsSync(legacyPin) ? legacyPin : undefined
  if (pinFile === undefined) return { ui, doc: ui, pinIgnored: false }

  const pinValue = langTag(pinFile)
  return pinValue === undefined
    ? { ui, doc: ui, pinIgnored: true }
    : { ui, doc: pinValue, pinIgnored: false }
}

/** The newline count of a file: what `wc -l` reports, and what the cursor holds. */
function newlineCount(file) {
  let count = 0
  const text = readFileSync(file, 'utf8')
  for (let index = 0; index < text.length; index += 1) {
    if (text[index] === '\n') count += 1
  }
  return count
}

/**
 * Whether a subagent is running this listener.
 *
 * DSH expresses the two relations separately and they can disagree: `roots()`
 * answers "was this agent created without an owning agent context" (a resumed
 * fork is still a root), while `parentSession` is durable session lineage. The
 * question here is the runtime one — is this agent working on someone else's
 * behalf right now — so ownership decides and lineage is only a fallback for a
 * deployment where the registry is not mounted. Not `isOwnedBy(agent.id, agent)`,
 * which asks whether the agent owns itself and is therefore always false.
 *
 * @param {import('@deepseek-ai/cordis').Context} ctx - the plugin context.
 * @param {{ id: string, session: { header: { parentSession?: string } } }} agent - the agent proposing the step.
 * @returns {boolean} true when the step belongs to a delegated child agent.
 */
function isSubagent(ctx, agent) {
  const agents = ctx.get('agents')
  if (agents !== undefined) return !agents.roots().includes(agent)
  return agent.session.header.parentSession !== undefined
}

/**
 * Build the notice shown to the user, and the instruction injected for the model.
 * Wording mirrors `volens-sync.sh` so the two implementations read alike.
 *
 * The two branches want opposite instructions about the log, so they are spelled
 * out rather than shared: a delta must read only its slice, while a rebuild is
 * there precisely because the log was rewritten and the slice is lines 1..M. A
 * "do not read the whole log" clause is true of the first and false of the
 * second, and leaving it in after a rewrite would tempt a partial rebuild of a
 * long log.
 *
 * @param {'delta' | 'rebuild'} kind - which branch fired.
 * @param {number} stale - the line count DESIGN.md reflected before this run, which is the pre-reset count on a rebuild.
 * @param {number} m - the log's newline count.
 * @param {string} docLang - the project's content language.
 * @param {boolean} pinIgnored - whether a pin was present and unusable.
 * @param {string} uiLang - the machine's communication language.
 * @returns {{ notice: string, context: string }} both texts, already localized.
 */
function renderMessages(kind, stale, m, docLang, pinIgnored, uiLang) {
  const note = pinIgnored
    ? uiLang === 'zh'
      ? `（内容语言 pin 被忽略：不是语言标签，改用 ${docLang}）`
      : ` (content-language pin ignored — not a language tag; using ${docLang})`
    : ''

  const notice = uiLang === 'zh'
    ? kind === 'rebuild'
      ? `📝 DECISION-LOG 被改写,光标已重置,将重建 DESIGN.md${note}`
      : `📝 DECISION-LOG 新增 ${stale}→${m} 行,「如意」将同步 DESIGN.md${note}`
    : kind === 'rebuild'
      ? `📝 DECISION-LOG was rewritten; cursor reset, DESIGN.md will rebuild${note}`
      : `📝 DECISION-LOG grew (${stale}→${m}); volens will sync DESIGN.md${note}`

  const opening = kind === 'rebuild'
    ? `The decision log docs/DECISION-LOG.md was rewritten and is now at line ${m}; docs/DESIGN.md is a stale snapshot of an earlier design (it reflected ${stale} lines, which no longer exist). Rebuild it from the whole log: read lines 1..${m} in full.`
    : `The decision log docs/DECISION-LOG.md is at line ${m}, but docs/DESIGN.md only reflects it through line ${stale}. The new content is exactly lines ${stale + 1}..${m} (previous line count ${stale}, current line count ${m}). Read only those lines.`

  const scope = kind === 'rebuild' ? 'Read the whole log before writing.' : 'Do not read the whole log.'

  const context = [
    opening,
    'Update docs/DESIGN.md from it, and end this turn with a write to docs/DESIGN.md:',
    'apply the change to the affected sections and the Design-decisions-in-force list, and',
    "always refresh the header line 'Last regenerated' to today. Even when no section",
    'changes are needed, still update that header — never skip the write, because the sync',
    "cursor advances only on DESIGN.md's mtime, and a no-write continuation re-injects",
    'this same delta and loops. If the write cannot land at all — permission denied, a',
    'read-only filesystem — stop after the first failure and tell the user plainly which',
    'file was refused and why: a silent failure leaves the design doc stale with nothing',
    `to explain it. ${scope}`,
    `Write the affected sections in ${docLang} (this project's content language —`,
    '.volens/lang, else ~/.config/volens/lang).',
  ].join(' ')

  return { notice, context }
}

/**
 * Mount the sync check.
 *
 * @param {import('@deepseek-ai/cordis').Context} ctx - the plugin context.
 */
export function apply(ctx) {
  ctx.on('agent/pre-step', async ({ agent, step, signal }, next) => {
    const decision = await next()
    if (decision.kind === 'reject' || signal.aborted) return decision
    if (step !== 1) return decision
    if (isSubagent(ctx, agent)) return decision

    const project = agent.session.header.cwd ?? process.cwd()
    const log = join(project, 'docs', 'DECISION-LOG.md')
    if (!existsSync(log)) return decision

    const design = join(project, 'docs', 'DESIGN.md')
    const cursor = join(project, 'docs', '.volens-cursor')

    const m = newlineCount(log)
    let n = 0
    if (existsSync(cursor)) {
      const parsed = Number.parseInt(readFileSync(cursor, 'utf8').trim(), 10)
      n = Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : 0
    }

    let kind
    let stale = n
    if (m < n) {
      // The log was rewritten or rolled back: reset first, then rebuild from zero.
      // `stale` keeps the pre-reset count, which is what the message reports as the
      // snapshot's out-of-date position; `n` becomes the rebuild's starting point.
      writeFileSync(cursor, '0')
      kind = 'rebuild'
      n = 0
    } else if (existsSync(design) && statSync(log).mtimeMs <= statSync(design).mtimeMs) {
      // DESIGN already reflects the log: fast-forward, silent.
      writeFileSync(cursor, String(m))
      return decision
    } else if (n < m) {
      kind = 'delta'
    } else {
      return decision
    }

    const { ui, doc, pinIgnored } = resolveLanguages(project)
    const { notice, context } = renderMessages(kind, stale, m, doc, pinIgnored, ui)

    return {
      ...decision,
      messages: [
        ...decision.messages,
        createUserMessage({
          content: [{ type: 'text', text: context }],
          source: { kind: 'plugin', plugin: name },
        }),
        createUserMessage({
          content: [{ type: 'text', text: notice }],
          source: { kind: 'plugin', plugin: name, form: 'notice', summary: notice },
        }),
      ],
    }
  })
}
