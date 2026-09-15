#!/usr/bin/env bash
# volens sync hook
# Registered on Stop + SessionStart by the plugin's hooks/hooks.json. Keeps
# docs/DESIGN.md derived from docs/DECISION-LOG.md using a line-count cursor.
#
# Switch semantics (one operation per event):
#   M < N          log was rewritten  -> reset cursor, inject full rebuild
#   design >= log  DESIGN already fresh -> fast-forward cursor, silent
#   N < M          new log lines      -> inject the exact delta N+1..M
#
# Machine state (docs/.volens-cursor) is owned by this script, never by Claude.
set -euo pipefail

# Event name, passed as an argument from hooks/hooks.json (e.g. "Stop" /
# "SessionStart"). Required in hookSpecificOutput.
EVENT="${1:-Stop}"

PROJ="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOG="$PROJ/docs/DECISION-LOG.md"
DESIGN="$PROJ/docs/DESIGN.md"
CURSOR="$PROJ/docs/.volens-cursor"

# No log, nothing to track.
[ -f "$LOG" ] || exit 0

M=$(wc -l < "$LOG" | tr -d '[:space:]')
N=0
[ -f "$CURSOR" ] && N=$(tr -d '[:space:]' < "$CURSOR")
N=${N:-0}

# Two languages. Communication (the user-facing notification) follows the
# user-level preference in ~/.config/volens/lang (a per-machine setting that
# cannot live in the plugin directory, which is shared and replaced on update).
# Content (what DESIGN.md is written in) follows the project's committed
# .claude/volens.lang, falling back to that same user-level preference. Both
# default to en.
LANG_UI="en"
if [ -f "$HOME/.config/volens/lang" ]; then
  LANG_UI=$(tr -d '[:space:]' < "$HOME/.config/volens/lang")
fi

LANG_DOC="$LANG_UI"
if [ -f "$PROJ/.claude/volens.lang" ]; then
  LANG_DOC=$(tr -d '[:space:]' < "$PROJ/.claude/volens.lang")
fi

emit() {
  # $1: "sync" -> delta inject, "reset" -> full rebuild
  local CONTEXT="The decision log docs/DECISION-LOG.md is at line ${M}, but docs/DESIGN.md only reflects it through line ${N}. The new content is exactly lines $((N+1))..${M} (previous line count ${N}, current line count ${M}). Read only those lines. Update docs/DESIGN.md from them, and end this turn with a write to docs/DESIGN.md: apply the delta to the affected sections and the Design-decisions-in-force list, and always refresh the header line 'Last regenerated' to today. Even when no section changes are needed, still update that header — never skip the write, because the sync cursor advances only on DESIGN.md's mtime, and a no-write continuation re-injects this same delta and loops. Do not read the whole log. Write the affected sections in ${LANG_DOC} (this project's content language — .claude/volens.lang, else ~/.config/volens/lang)."

  # The user-facing notice follows the injection: if we inject, we say so; if the
  # user sees nothing, nothing was injected. systemMessage is a TOP-LEVEL field —
  # nested inside hookSpecificOutput it is silently ignored, and Claude Code logs
  # only "unrecognized keys (ignored)". Both Stop and SessionStart render it; the
  # earlier claim that SessionStart ignores it was never true and was never
  # testable while the placement was wrong. (Verified 2026-09-14 against Claude
  # Code's own session record: a payload carrying both placements produced a
  # single `hook_system_message` attachment, from the top-level key.)
  local MSG
  if [ "$LANG_UI" = "zh" ]; then
    if [ "$1" = "reset" ]; then
      MSG="📝 DECISION-LOG 被改写,光标已重置,将重建 DESIGN.md"
    else
      MSG="📝 DECISION-LOG 新增 ${N}→${M} 行,Claude 将同步 DESIGN.md"
    fi
  else
    if [ "$1" = "reset" ]; then
      MSG="📝 DECISION-LOG was rewritten; cursor reset, DESIGN.md will rebuild"
    else
      MSG="📝 DECISION-LOG grew (${N}→${M}); Claude will sync DESIGN.md"
    fi
  fi
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$MSG" "$EVENT" "$CONTEXT"
}

if [ "$M" -lt "$N" ]; then
  # Log was rewritten/rolled back: reset cursor first (emit embeds N), then rebuild.
  echo 0 > "$CURSOR"; N=0
  emit reset
elif [ -f "$DESIGN" ] && [ ! "$LOG" -nt "$DESIGN" ]; then
  # DESIGN already covers the log: fast-forward cursor, silent.
  echo "$M" > "$CURSOR"
elif [ "$N" -lt "$M" ]; then
  # New log lines: inject the delta. Cursor stays until regeneration confirms.
  emit sync
fi

exit 0
