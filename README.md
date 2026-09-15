# volens (如意)

> English | [中文](README_zh.md)

**volens** is a plugin built for Claude Code (it may support other agents later). It maintains a structure that keeps a project's documentation in step with its decisions and permanently fresh — the design doc follows every decision you make, and you never have to think about it. And you only need to send `/volens:volens` once in a project: the spell stays cast, with no need to cast it again each time you change your mind.

## Why you need volens

Thanks to how quickly models improve and how mature agent products have become, our ideas can go from thought to working code with an agent's help, without being shut out by technical know-how we don't have. But on the way from a rough idea to a finished piece of work, something else happens. As we flesh the idea out, pick apart each detail, and learn and choose between technologies while building, the blueprint in our head keeps changing — changes that can overturn earlier decisions, or leave us going back and forth on the same one. And over time, hand-maintained design docs drift quietly out of date: they mislead us, they leave the project messy, and they make the model more likely to hallucinate.

volens is a plugin built to solve exactly that:

- It maintains an **append-only decision log** (`docs/DECISION-LOG.md`), recording every decision we make so that each one is traceable.

- It **derives the design doc from that log** (`docs/DESIGN.md`) and can update it automatically, keeping the design doc in step with decisions and permanently fresh, without us having to care.

- Whether you're landing a new idea or iterating on an existing project, volens can help. Just send `/volens:volens` in Claude Code's input box, and volens puts `docs/DECISION-LOG.md` in place in your project and keeps the design snapshot following your decisions.

volens keeps the design doc in step with your thinking. Let Claude Code implement code from the design doc, and the project comes out the way you want it.

---

## How it works

Run `/volens:volens` once and volens surveys what already exists in the project (**it will not overwrite anything**), then puts the following files in place:

- **The contract module in `CLAUDE.md`** — if the file doesn't exist, it creates one containing only the contract module; if it does, it inserts or updates the module between the markers, holding the documentation model + working agreements. Nothing else in the file is touched.
- **`docs/DECISION-LOG.md`** — an append-only **decision log**, seeded with one entry recording the adoption of this structure. Every later design decision is appended here; history only grows, never changes.
- **`docs/DESIGN.md`** — a **design snapshot** derived from the log. An existing project gets one at scaffold time; a brand-new project skips it, and the hook generates it from the decision log on the first sync.
- **`.claude/volens.lang`** — the "project-level decision" of which language this project's docs are recorded in (e.g. `zh`/`en`), asked once and committed.
- **`docs/.volens-cursor`** — the hook's cursor: it records how far into the log the design doc has been reflected. Pure runtime state; written to `.gitignore`, never committed.

The sync script itself ships with the plugin and is **never written into your project** — the files above are the only ones volens adds there.

With those in place, day-to-day freshness runs on an **append → notice → incremental sync** loop:

1. **The decision lands** — each time you make a design decision, append an entry to `docs/DECISION-LOG.md` (Context → Decision → Consequences). Append only; never rewrite history.
2. **The hook notices** — on `Stop` (a reply ends) and `SessionStart` (a session begins) the sync script runs automatically and compares the log's line count against the `docs/.volens-cursor` cursor.
3. **The delta is injected** — if the log has lines beyond the cursor, exactly those lines are handed to Claude Code as additional context to sync from; if the design doc is already current, the cursor is silently fast-forwarded.
4. **Only the affected parts are regenerated** — Claude Code updates only the affected sections of the design doc, the "Design decisions in force" list, and the "Last regenerated" header. It doesn't re-read the whole log or rewrite the whole document. If the log was rewritten or rolled back (line count drops), the cursor is reset and a full rebuild of `docs/DESIGN.md` is requested.

So `docs/DESIGN.md` is always a snapshot of the design "as of now" — derived from the log, kept fresh by the hook. You make the decisions; volens handles the rest.

---

## Install and first run

Install volens in Claude Code. Two prerequisites:

- `git` is on your PATH
- `git` can reach GitHub

1. Add the marketplace:

   ```
   /plugin marketplace add https://github.com/funcpn/volens.git
   ```

   > Use the full URL. Don't use the `funcpn/volens` shorthand — it resolves to SSH, which fails on a machine with no GitHub key configured.

2. Install from the marketplace:

   ```
   /plugin install volens@volens
   ```

3. Confirm it installed: run `claude plugin list` and look for `volens@volens` with status `✔ enabled`.

### How to use

Claude Code has to be **restarted once** for the plugin to load. After that, in the project you want to bring under the structure, run:

```
/volens:volens
```

It surveys what already exists (**it will not overwrite anything**), sets the documentation language (once), ensures the CLAUDE.md contract module is in place, seeds `docs/DECISION-LOG.md`, and confirms the sync hook is live. From then on, whenever a design decision changes, append an entry to the log; the hook handles the rest.

### Alternative: download the ZIP

If `git` can't reach GitHub, download instead:

1. On this repository's main page, click the green **Code** button → **Download ZIP**
2. Unzip it. The folder name carries a branch suffix (e.g. `volens-main`) — **rename it to `volens`**
3. Move the whole folder into your skills directory:
   - macOS / Linux: `~/.claude/skills/`
   - Windows: `%USERPROFILE%\.claude\skills\`

   Create that directory if it doesn't exist. You should end up with `…/.claude/skills/volens/`, containing `.claude-plugin`, `skills` and `hooks`.
4. Restart Claude Code. Run `claude plugin list` and confirm you see `volens@skills-dir` with status `✔ loaded`

> ⚠️ **This route has no automatic updates.** When volens ships a new version there'll be no notice — you'll have to come back and download it again yourself. **Use the marketplace if you can.**

---

## License

This project is open source under the MIT license — see [LICENSE](LICENSE).
