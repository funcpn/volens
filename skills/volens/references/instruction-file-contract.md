<!-- === volens contract start === -->
## Documentation model
<!-- How the docs layers relate. DESIGN.md is derived and hook-maintained; never hand-edit it as a source of truth. -->
- **This file** — the project's instruction file, auto-loaded every session. This contract block is the docs-system part of it; the project's stable facts and conventions live here too.
- **docs/DECISION-LOG.md** — append-only design decision history. Context → Decision → Consequences; supersede by adding a new dated entry, never edit old ones.
- **docs/DESIGN.md** — derived snapshot of the current state. Regenerated from code + DECISION-LOG, never treated as a hand-maintained source of truth.
- A hook keeps DESIGN.md fresh: it tracks how many log lines DESIGN.md reflects (`docs/.volens-cursor`) and prompts the exact delta. When a delta prompt appears, update only the affected sections and the "Design decisions in force" list, and always refresh the "Last regenerated" header — do not re-read the whole log. Never end a delta prompt without writing DESIGN.md: the header refresh is the minimum write that lets the cursor advance on mtime evidence.
- Content under `docs/` (log entries and DESIGN.md updates) is written in this project's content language: `.volens/lang` if present, else the user-level `${XDG_CONFIG_HOME:-$HOME/.config}/volens/lang` (default `en`).

## Working agreements
<!-- Behaviors that must hold every session. -->
- `docs/DECISION-LOG.md` is append-only: when a design decision changes, add a new dated entry; never edit old entries.
- `docs/DESIGN.md` is derived and hook-maintained: regenerate only the prompted delta, never hand-rewrite it wholesale.
<!-- === volens contract end === -->
