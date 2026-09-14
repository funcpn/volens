# Decision Log

Append-only record of design decisions. Never rewrite history — add a new dated entry when a decision changes. A newer entry supersedes older ones where they conflict.

*Content language follows the project's `.claude/volens.lang`, else the skill's `.lang` (default `en`); this template defines the structure only.*

## Entry template

### YYYY-MM-DD — <short decision title>
- **Context:** why this decision is needed (forces at play, what changed)
- **Decision:** what we decided to do
- **Consequences:** what becomes easier / harder
- **Supersedes:** (reference to the decision this replaces, if any)

---

## Log

### YYYY-MM-DD — Adopt the volens documentation structure
- **Context:** design docs kept going stale as the codebase evolved; decisions were being made without a record of why.
- **Decision:** use CLAUDE.md (stable facts + volens's marker-delimited contract module) + this append-only DECISION-LOG + a derived DESIGN.md kept fresh by the sync hook.
- **Consequences:** less stale-doc damage; the "why" of decisions is preserved; requires the discipline of appending rather than editing.
