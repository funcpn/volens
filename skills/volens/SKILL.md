---
name: volens
description: Set up and maintain a documentation structure that survives a moving design — a contract module inside CLAUDE.md (documentation model + working agreements), docs/DECISION-LOG.md (append-only design decision log), and docs/DESIGN.md (derived current-state snapshot kept fresh automatically by a hook). Use when starting work on a new or unfamiliar codebase, when recording a design decision, or when docs need a refresh.
license: MIT
---

# volens

Scaffold and maintain a documentation structure that survives a moving design. Three layers with different update frequencies:

1. **CLAUDE.md** — the project's instruction file, auto-loaded every session. volens does not author the file; it maintains one **contract module** inside it (the documentation model + working agreements, wrapped in markers). Repo facts and conventions are the user's to supply (or their agent's init command). The module is English when volens creates the file, and follows the file's dominant language when inserted into an existing CLAUDE.md.
2. **docs/DECISION-LOG.md** — append-only design decision log. Each entry: Context → Decision → Consequences. Design changes are recorded as new entries that supersede old ones — never rewrite history.
3. **docs/DESIGN.md** — derived current-state snapshot. Regenerated from code + DECISION-LOG by the hook; never hand-maintained as the source of truth.

## Documentation model

The layers are split by lifetime: CLAUDE.md holds what is stable (of which volens maintains only its contract module), the log accumulates history without rewriting, and DESIGN.md is a derived snapshot of the latest state.

A hook keeps DESIGN.md in sync automatically. It tracks how many log lines DESIGN.md reflects (a cursor file, `docs/.volens-cursor`) and, when new entries land, injects the exact delta (lines N+1..M) as additionalContext. Regenerate only that delta — the affected sections and the "Design decisions in force" list — and always refresh the "Last regenerated" header. Never end a delta prompt without writing DESIGN.md: even when no section change is needed, the header refresh is the required minimum write, because the hook's cursor advances only on mtime evidence and a no-write continuation re-injects the same delta and loops. Do not re-read the whole log.

Content under `docs/` (log entries and DESIGN.md) is written in the project's **content language**: `.claude/volens.lang` if present, else the user-level `~/.config/volens/lang` (default `en`). The language volens *talks* to the user in is always that user-level preference, independent of any project. CLAUDE.md's language is the project's own; the contract module follows it (English when volens creates the file).

## When to use

- Starting work on a new or unfamiliar codebase not yet under volens → **scaffold** mode.
- A design decision changes and should be recorded → **append** mode.
- Docs have gone stale and need a refresh → **refresh** mode.

## Modes

### Scaffold (new / unfamiliar codebase)

First-adoption only. **If this project is already under volens — its CLAUDE.md carries the `<!-- volens contract start/end -->` markers, or `docs/DECISION-LOG.md` exists with a real history — do not scaffold. Never create, seed, overwrite, or regenerate `DECISION-LOG.md` or `DESIGN.md`.** Run a *refresh-verify* instead: apply the Refresh procedure, changing only genuine drift — contract module stale or missing → re-sync it (step 4 logic); `DESIGN.md` behind the log → apply the delta (if the hook is registered it usually already did this at SessionStart); `.claude/volens.lang` absent → ask the content language once (step 2 logic); `docs/.volens-cursor` missing from `.gitignore` → add it (step 7 logic). Then report the state. Repairs, never rebuilds: the create/seed steps below exist only for the first adoption.

1. **Survey.** Check what already exists: `CLAUDE.md`, `docs/`, `.gitignore`, existing notes. Integrate — don't clobber.
2. **Set the two languages.** volens separates *communication* (how it talks to the user) from *content* (what language this project's docs are written in).
   - **Communication language — the user-level preference.** Read `~/.config/volens/lang`. If unset, ask the user in one line (e.g. "文档用什么语言?中文或 English?") and write the answer there — a one-time, per-machine preference. It lives outside every project and outside the plugin directory, so updating volens never touches it. Every word volens says in this scaffold — questions, explanations, the closing report — uses it. No project overrides it: in a project whose docs are English, volens still talks to the user in the user's own language.
   - **Content language — the project `.lang`.** Read `<project>/.claude/volens.lang`. If it exists, that is this project's documentation language — do not ask again. If it does not, ask once, framed in the communication language and offering it as the default ("这个项目的文档用什么语言记录?默认同你的设置"), then write the answer into `.claude/volens.lang`. That file is a *committed project decision*: it ships in the repo, so every contributor and future clone shares it. A project decides once — the file's presence *is* the "already asked" signal.
   - Neither language governs CLAUDE.md: the contract module follows the rule in step 4.
3. **First exploration.** Traverse the codebase (respecting `.gitignore`): identify subsystems, entry points, config files, build/test/lint/run commands, conventions, and known traps. Read README and key configs.
4. **Ensure the contract module is present in CLAUDE.md**, using `references/claude-md-contract.md` — the canonical English module, wrapped in `<!-- volens contract start/end -->` markers. Do not author any other CLAUDE.md content.
   - **No CLAUDE.md exists** → create one containing only the module, in English (the canonical block as-is).
   - **CLAUDE.md exists** → insert or refresh only the module: if the markers are present, replace everything between them (inclusive) with the current module; if not, append the module at the end. Write the module in the file's dominant language — translate the canonical block, headings included. If the file's language is genuinely mixed, ask rather than guess.
   - Never modify any text outside the markers — not even to fix an error; report errors instead.
5. **Create docs/DECISION-LOG.md** — only if it does not already exist (see the guard above; creation is first-adoption, never rewrite or re-seed an existing log). Using `references/decision-log-template.md`, in the project's content language (resolved in step 2). Seed it with one entry recording that this structure was adopted. For an **existing project**, add a second baseline entry stating that the design documented in DESIGN.md was inferred from the code, not from a decision trail. Never reverse-generate the log into fabricated decisions.
6. **Create docs/DESIGN.md** — only if it does not already exist (see the guard above; never hand-regenerate an existing DESIGN). The derived current-state snapshot, in the project's content language (resolved in step 2). Create it *after* the log, so the first hook run fast-forwards the cursor silently instead of injecting the seed back.
   - **New project:** skip for now — the first hook injection creates DESIGN.md from the seed log.
   - **Existing project:** generate DESIGN.md from the step-3 exploration; list inferred design choices under "Design decisions in force", labeled as inferred observations of the current state.
7. **Make the hook effective in this project.** The sync script ships with the plugin — **nothing is copied into the project and no settings file is edited.** Two things remain:
   - Add `docs/.volens-cursor` to the project's `.gitignore` — it is hook-maintained machine state, never committed.
   - State that the hook now runs on its own, at every `Stop` and `SessionStart`. If this agent has no hook mechanism, say so plainly and tell the user that freshness falls back to the manual path in **Append** — do not pretend the automation is in place.
8. **Report.** Summarize what was created, what still needs filling, and open questions. State plainly what the CLAUDE.md contract module contains and what language it was written in, and that this project's docs language is pinned in `.claude/volens.lang` (commit that file with the repo). Offer to put personal notes in `CLAUDE.local.md` (gitignored) if the user wants them separate from team-shared files.

### Append (a design decision changes)

1. Add a new dated entry to `docs/DECISION-LOG.md` (Context → Decision → Consequences; mark `Supersedes:` when replacing an older decision). Write the entry in the project's content language (`.claude/volens.lang`, else the user-level `~/.config/volens/lang`).
2. DESIGN.md is regenerated by the hook on the next Stop / SessionStart. If the hook is not installed, update the affected DESIGN.md sections + "Last regenerated" header manually.

### Refresh (docs have gone stale)

1. Check DECISION-LOG for entries not yet reflected in DESIGN.md; apply the delta (affected sections + "Design decisions in force" + header) in the project's content language (as in Append).
2. Re-sync the contract module in CLAUDE.md: if the markers are gone (e.g. a later `/init` rewrite dropped them), re-insert; if stale, replace between the markers with the current module from `references/claude-md-contract.md`. Match the file's dominant language. Do not touch the rest of the file.

## Rules

- volens touches CLAUDE.md only through its contract module (markers to markers). The module is English when volens creates the file and follows the file's dominant language when inserted into an existing one; the rest of the file's language and length are not constrained.
- The DECISION-LOG is where "why we changed" lives; never delete old entries.
- DESIGN.md is derived: regenerate only the delta the hook prompts; never hand-rewrite it wholesale.
- volens never re-scaffolds a project already under volens: if the contract markers are present, or `DECISION-LOG.md` has a real history, nothing is created, seeded, overwritten, or regenerated — a bare run there is a refresh-verify, not a rebuild.
- Content under `docs/` (log entries and DESIGN.md) is written in the project's content language: `.claude/volens.lang` if present, else the user-level `~/.config/volens/lang` (default `en`).
- The language volens *talks* to the user in is always the user-level preference, never the project's content language.
- `.claude/volens.lang` is a committed project decision — never gitignore it; when it is absent, ask the project's content language once (never silently default), framed in the user-level language.
- Never put secrets or credentials into CLAUDE.md or docs — they get committed to the repo.
