# volens (如意)

> English | [中文](README_zh.md)

**volens** is a plugin for coding agents — Claude Code and Codex today. It maintains a structure that keeps a project's documentation in step with its decisions and permanently fresh — the design doc follows every decision you make, and you never have to think about it. And you only need to set it up once in a project: the spell stays cast, with no need to cast it again each time you change your mind.

## Why you need volens

Thanks to how quickly models improve and how mature agent products have become, our ideas can go from thought to working code with an agent's help, without being shut out by technical know-how we don't have. But on the way from a rough idea to a finished piece of work, something else happens. As we flesh the idea out, pick apart each detail, and learn and choose between technologies while building, the blueprint in our head keeps changing — changes that can overturn earlier decisions, or leave us going back and forth on the same one. And over time, hand-maintained design docs drift quietly out of date: they mislead us, they leave the project messy, and they make the model more likely to hallucinate.

volens is a plugin built to solve exactly that:

- It maintains an **append-only decision log** (`docs/DECISION-LOG.md`), recording every decision we make so that each one is traceable.

- It **derives the design doc from that log** (`docs/DESIGN.md`) and can update it automatically, keeping the design doc in step with decisions and permanently fresh, without us having to care.

- Whether you're landing a new idea or iterating on an existing project, volens can help. On Claude Code, send `/volens:volens` in the input box; on Codex, have the agent use volens's skill once. volens then puts `docs/DECISION-LOG.md` in place in your project and keeps the design snapshot following your decisions.

volens keeps the design doc in step with your thinking. Let your agent implement code from the design doc, and the project comes out the way you want it.

---

## How it works

Run volens once in a project (Claude Code: `/volens:volens`; Codex: `$volens:volens`). It first surveys what already exists in the project (**it will not overwrite anything**), then puts the following files in place:

- **The contract module in the project's instruction file** — `CLAUDE.md` on Claude Code, `AGENTS.md` on Codex. If the file doesn't exist, it creates one containing only the contract module; if it does, it inserts or updates the module between the markers, holding the documentation model + working agreements. Nothing else in the file is touched.
- **`docs/DECISION-LOG.md`** — an append-only **decision log**, seeded with one entry recording the adoption of this structure. Every later design decision is appended here; history only grows, never changes.
- **`docs/DESIGN.md`** — a **design snapshot** derived from the log. An existing project gets one at scaffold time; a brand-new project skips it, and the hook generates it from the decision log on the first sync.
- **`.volens/lang`** — the "project-level decision" of which language this project's docs are recorded in (e.g. `zh`/`en`), asked once and committed. (Earlier versions wrote it to `.claude/volens.lang`; an older project's file still works, and volens moves it to the new location on the next refresh.)
- **`docs/.volens-cursor`** — the hook's cursor: it records how far into the log the design doc has been reflected. Pure runtime state; written to `.gitignore`, never committed.

The sync script itself ships with the plugin and is **never written into your project** — the files above are the only ones volens adds there.

With those in place, day-to-day freshness runs on an **append → notice → incremental sync** loop:

1. **The decision lands** — each time you make a design decision, append an entry to `docs/DECISION-LOG.md` (Context → Decision → Consequences). Append only; never rewrite history.
2. **The hook notices** — the sync script runs automatically at every session moment (Claude Code: `Stop` (a reply ends) and `SessionStart` (a session begins); Codex: `UserPromptSubmit`, on every message you send), comparing the log's line count against the `docs/.volens-cursor` cursor.
3. **The delta is injected** — if the log has lines beyond the cursor, exactly those lines are handed to the agent as additional context to sync from; if the design doc is already current, the cursor is silently fast-forwarded.
4. **Only the affected parts are regenerated** — the agent updates only the affected sections of the design doc, the "Design decisions in force" list, and the "Last regenerated" header. It doesn't re-read the whole log or rewrite the whole document. If the log was rewritten or rolled back (line count drops), the cursor is reset and a full rebuild of `docs/DESIGN.md` is requested.

So `docs/DESIGN.md` is always a snapshot of the design "as of now" — derived from the log, kept fresh by the hook. You make the decisions; volens handles the rest.

---

## What the hook does — and doesn't

The sync script ships inside the plugin. On Claude Code it is registered by `hooks/hooks.json` and runs on `Stop` (a reply ends) and `SessionStart` (a session starts, is cleared, or is compacted); on Codex it is registered by `hooks/hooks-codex.json` and runs on `UserPromptSubmit` only — every message you send. It is one shell script either way.

**What it reads** — the *line count* of `docs/DECISION-LOG.md`, the number stored in `docs/.volens-cursor`, the *modification time* of `docs/DESIGN.md`, and your language preference (`~/.config/volens/lang` — or under `XDG_CONFIG_HOME` when that is set — or the project's `.volens/lang`).

That is the whole list. It never reads the contents of your log, your design doc, or your source code — it counts lines in one file and compares one timestamp.

**What it writes** — exactly one file, `docs/.volens-cursor`. It does not write `docs/DESIGN.md` itself: it emits a prompt asking the agent to, and the cursor advances only once that write has landed.

**What it doesn't do:**

- **No network.** No HTTP, no sockets, no telemetry, no analytics. Nothing leaves your machine.
- **No writes outside `docs/`.** It never touches your source or your instruction file, and it only ever reads `.volens/lang`.
- **No execution of anything from your project.** The script is fixed and ships with the plugin.
- **No blocking.** It always exits 0, so it can only ever add context to the conversation — it cannot stop a turn or refuse a tool call.

When there is nothing to sync it prints nothing. **Silence means nothing was injected — not that something failed.**

---

## Install and first run

Prerequisites:

- `git` is on your PATH
- `git` can reach GitHub

### Install in Claude Code

1. Add the marketplace:

   ```
   /plugin marketplace add https://github.com/funcpn/volens.git
   ```

2. Install from the marketplace:

   ```
   /plugin install volens@volens
   ```

3. Confirm it installed: run `claude plugin list` and look for `volens@volens` with status `✔ enabled`.

### Install in Codex

volens installs into Codex as a plugin too, through Codex's own marketplace mechanism:

1. Add the marketplace:

   ```
   codex plugin marketplace add https://github.com/funcpn/volens
   ```

2. Install from the marketplace:

   ```
   codex plugin add volens@volens
   ```

3. Confirm it installed: run `codex plugin list` and look for `volens` with status `installed, enabled`.

### Alternative: install from a ZIP

If `git` can't reach GitHub, both Claude Code and Codex can install from a download instead. Downloading and unpacking are the same either way; putting the folder in place is where they diverge.

Get the folder first:

1. Open this repository's **Releases** page and, under the newest version, download **Source code (zip)** — or the packaged zip, if that version attaches one
2. Unpack it. The folder name carries a suffix (`volens-0.2.0`, `volens-main`, …) — **rename it to `volens`**

**Claude Code** — move the whole folder into your skills directory:

- macOS / Linux: `~/.claude/skills/`
- Windows: `%USERPROFILE%\.claude\skills\`

Create that directory if it doesn't exist. You should end up with `…/.claude/skills/volens/`, containing `.claude-plugin`, `skills` and `hooks`. Restart Claude Code, then run `claude plugin list` and confirm you see `volens@skills-dir` with status `✔ loaded`.

**Codex** — the folder can live anywhere (say `~/plugins/volens`); add it as a local marketplace:

```
codex plugin marketplace add ~/plugins/volens
codex plugin add volens@volens
```

Run `codex plugin list` and confirm the status is `installed, enabled`. Your first session will likewise show `Hooks need review` — choose **Trust all and continue**.

---

## How to use it

The plugin only loads after you **restart your agent** once. After that, in the project you want to bring under the structure, run:

On Claude Code:

```
/volens:volens
```

On Codex:

```
$volens:volens
```
>**Codex asks you to trust the hooks once, on the first run.** Your first Codex session will show `Hooks need review` — choose **Trust all and continue**. Without it the plugin is installed, but the design snapshot never updates.

It surveys what already exists (**it will not overwrite anything**), sets the documentation language (once), ensures the contract module is in place, seeds `docs/DECISION-LOG.md`, and confirms the sync hook is live. From then on, whenever a design decision changes, append an entry to the log; the hook handles the rest.

---

## License

This project is open source under the MIT license — see [LICENSE](LICENSE).
