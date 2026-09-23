# volens-dsh

**volens on DeepSeek Harness.** It keeps a project's documentation in step with its decisions: an append-only decision log (`docs/DECISION-LOG.md`), a design snapshot derived from it (`docs/DESIGN.md`), and a sync that keeps the snapshot fresh without being asked.

This package is the **DSH half** of volens. The full project — the same discipline for Claude Code and Codex — is at <https://github.com/funcpn/volens> ([中文说明](https://github.com/funcpn/volens/blob/main/README_zh.md)).

## Install

DSH loads plugins into its own process, and it discovers skills from filesystem directories rather than from a plugin's manifest. So volens installs in **two steps**, one for each half.

1. Install the plugin into a profile:

   ```sh
   dsh plugin --profile web add volens-dsh
   ```

   This is `pnpm add` run inside `~/.dsh/profiles/web`; `web` is the shipped web template, so swap in your own profile name if it differs. The package declares a `dsh.bundle`, so installing it makes its layer available to that profile.

2. Make the skill discoverable. Get the project repository first, then link its skill into a directory DSH scans:

   ```sh
   git clone https://github.com/funcpn/volens
   ln -s /path/to/volens/skills/volens ~/.agents/skills/volens
   ```

   `/path/to/volens` is that clone. DSH scans `~/.agents/skills`, `~/.dsh/skills`, and the project-local `.agents/skills` and `.dsh/skills`; a symlink is fine, because DSH follows it. Type `/` in the input box and `volens` should be in the menu — DSH has no plugin namespace, so it is invoked as `/volens`.

3. Restart DSH. The profile's patch and the plugin module are read at process start.

No bash is involved: unlike the Claude Code and Codex halves, this one is JavaScript running inside the agent's own process.

## What it does

Registered on one event only — `agent/pre-step`, gated to the first step of a turn, which is the turn head. Subagent sessions are skipped. Once per turn it reads the log's **newline count** `M` (the quantity `wc -l` reports) and the number `N` stored in `docs/.volens-cursor`, then takes one branch:

| Condition | What happens |
|---|---|
| `M < N` — the log was rewritten | the cursor is reset to `0` and a **full rebuild** is injected: read lines `1..M` in full and rebuild `docs/DESIGN.md` |
| `docs/DESIGN.md` is at least as new as the log | the cursor is fast-forwarded to `M`, silently |
| `N < M` — new entries | exactly lines `N+1..M` are injected as the delta to apply |
| otherwise | nothing is injected |

The injected instruction asks for the affected sections, the "Design decisions in force" list and the "Last regenerated" header to be updated, because the cursor advances on `docs/DESIGN.md`'s modification time — a turn that receives a delta and writes nothing would be handed the same delta again.

The user-visible notice rides along as a collapsed context row (a message with `form: 'notice'`), not as a line of its own. Synchronization does not depend on seeing it.

## What it reads and writes

It reads the newline count of `docs/DECISION-LOG.md`, the number in `docs/.volens-cursor`, the modification time of `docs/DESIGN.md`, and the content-language pin — `.volens/lang`, the legacy `.claude/volens.lang`, else `${XDG_CONFIG_HOME:-~/.config}/volens/lang`. A pin that is not a language tag is ignored, and the next notice says which language is actually in force.

It writes exactly one file, `docs/.volens-cursor`. It never writes `docs/DESIGN.md` itself; it asks the agent to.

## What it doesn't do

- **No network.** No HTTP, no sockets, no telemetry, no analytics. Nothing leaves your machine.
- **No writes outside `docs/`.** It never touches your source or your instruction file.
- **No execution of anything from your project.** The plugin is fixed and ships inside this package.
- **No blocking.** When there is nothing to sync it returns no decision, so it can only ever add context to a turn.

## Peer dependencies

`@deepseek-ai/cordis`, `@deepseek-ai/dsh-agent` and `@deepseek-ai/dsh-llm` come from your DSH installation: they are declared as peers (`*`) rather than fetched. The published package's `files` list is `index.js` and `cordis.patch.yml`; npm adds `package.json`, this README and the license, and nothing else.

This is the second implementation of volens' sync semantics; `hooks/volens-sync.sh`, which serves Claude Code and Codex as a child process, stays the reference. An inconsistency between the two is a defect, not a harness difference.

## Updating

`dsh plugin add` copies the package into the profile rather than linking to it, so re-running the add is how an update arrives:

```sh
dsh plugin --profile web add volens-dsh
```

The skill is a symlink into your repository and needs nothing.

## License

MIT — see [LICENSE](LICENSE).
