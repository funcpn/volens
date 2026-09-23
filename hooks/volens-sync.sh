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

# Claude Code hands a Stop hook a JSON payload on stdin. If this Stop is the
# follow-up to a continuation we ourselves triggered, do nothing: Claude Code
# documents stop_hook_active for exactly this — "check stop_hook_active in the
# input and return success while it's true". Without it, a write that never
# lands (permission denied, read-only filesystem, a model that doesn't comply)
# re-injects the same delta on every subsequent Stop and the session never ends
# — measured at 98 injections in 240s before the run was killed by hand.
# The cost of skipping is at most a deferred cursor fast-forward: the next
# user-turn Stop (where the flag is false) or SessionStart catches it up.
# Scoped to Stop on purpose — the field belongs to the Stop family and is not
# sent to SessionStart, so a stray value there must not suppress the injection.
if [ "$EVENT" = "Stop" ] && [ ! -t 0 ]; then
  # `read -t` bounds the wait. A bare `cat` blocks forever when stdin is neither
  # a terminal nor a closed pipe — which is exactly what happens when a model or
  # a person runs the hook by hand inside a harness that holds stdin open. CC
  # itself always writes the payload and closes the pipe, so this returns at once
  # in normal operation.
  HOOK_INPUT=""
  IFS= read -r -d '' -t 2 HOOK_INPUT 2>/dev/null || true
  case "$(printf '%s' "$HOOK_INPUT" | tr -d ' \n\t')" in
    *'"stop_hook_active":true'*) exit 0 ;;
  esac
fi

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
# user-level preference at XDG_CONFIG_HOME/volens/lang, else ~/.config/volens/lang
# (a per-machine setting that
# cannot live in the plugin directory, which is shared and replaced on update).
# Content (what DESIGN.md is written in) follows the project's committed pin at
# .volens/lang, falling back to that same user-level preference. Both default
# to en. Projects scaffolded before the pin moved keep theirs at
# .claude/volens.lang, which is still read — the skill moves it on the next
# refresh; no project has to be touched by hand.
# XDG_CONFIG_HOME wins when it is set and non-empty, as it does for other CLIs.

# Read a language tag, or nothing. The pin is the one project-controlled string
# that reaches the injected instruction, so it is validated rather than embedded
# as found: two or three letters, then up to three subtags (`zh`, `zh-CN`,
# `zh-Hans-CN`), nothing else. tr -d '[:space:]' removes only ASCII whitespace —
# a no-break space, or a whole sentence, survives it — which is why the shape is
# checked here.
lang_tag() {
  local v
  v=$(tr -d '[:space:]' < "$1")
  if [[ "$v" =~ ^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8}){0,3}$ ]]; then
    printf '%s' "$v"
  fi
}

LANG_UI="en"
LANG_UI_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/volens/lang"
if [ -f "$LANG_UI_FILE" ]; then
  LANG_UI=$(lang_tag "$LANG_UI_FILE")
  LANG_UI="${LANG_UI:-en}"
fi

# The project's pin. A file that holds no language tag is treated the same as one
# that is missing — the fallback chain is unchanged — and the fact is remembered
# so the next notice can say so, because otherwise an ignored pin and a working
# one look identical from outside.
LANG_DOC="$LANG_UI"
LANG_PIN_IGNORED=""
LANG_PIN_FILE=""
if [ -f "$PROJ/.volens/lang" ]; then
  LANG_PIN_FILE="$PROJ/.volens/lang"
elif [ -f "$PROJ/.claude/volens.lang" ]; then
  LANG_PIN_FILE="$PROJ/.claude/volens.lang"
fi
if [ -n "$LANG_PIN_FILE" ]; then
  PINNED=$(lang_tag "$LANG_PIN_FILE")
  if [ -n "$PINNED" ]; then
    LANG_DOC="$PINNED"
  else
    LANG_PIN_IGNORED="yes"
  fi
fi

# Escape a string for embedding as a JSON value. Backslash is replaced FIRST:
# every later substitution introduces backslashes of its own, and escaping those
# would double them. Uses bash parameter substitution rather than a per-character
# loop — the loop form is O(n^2) and takes tens of seconds on Windows Git Bash.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

emit() {
  # $1: "sync" -> delta inject, "reset" -> full rebuild
  # $2: on a rebuild, the pre-reset cursor — the position DESIGN.md had reached
  #     before the log was rewritten, which is what the message reports as stale.
  # The two branches want opposite instructions about the log, so they are spelled
  # out rather than shared: a delta must read only its slice, while a rebuild is
  # there precisely because the log was rewritten and the slice is lines 1..M — a
  # "Do not read the whole log" clause is true of the first and false of the second,
  # and after a rewrite leaving it in would tempt a partial rebuild of a long log.
  local OPEN SCOPE STALE_REF
  if [ "$1" = "reset" ]; then
    STALE_REF="${2:-$N}"
    OPEN="The decision log docs/DECISION-LOG.md was rewritten and is now at line ${M}; docs/DESIGN.md is a stale snapshot of an earlier design (it reflected ${STALE_REF} lines, which no longer exist). Rebuild it from the whole log: read lines 1..${M} in full."
    SCOPE="Read the whole log before writing."
  else
    OPEN="The decision log docs/DECISION-LOG.md is at line ${M}, but docs/DESIGN.md only reflects it through line ${N}. The new content is exactly lines $((N+1))..${M} (previous line count ${N}, current line count ${M}). Read only those lines."
    SCOPE="Do not read the whole log."
  fi
  local CONTEXT="${OPEN} Update docs/DESIGN.md from it, and end this turn with a write to docs/DESIGN.md: apply the change to the affected sections and the Design-decisions-in-force list, and always refresh the header line 'Last regenerated' to today. Even when no section changes are needed, still update that header — never skip the write, because the sync cursor advances only on DESIGN.md's mtime, and a no-write continuation re-injects this same delta and loops. If the write cannot land at all — permission denied, a read-only filesystem — stop after the first failure and tell the user plainly which file was refused and why: a silent failure leaves the design doc stale with nothing to explain it. ${SCOPE} Write the affected sections in ${LANG_DOC} (this project's content language — .volens/lang, else ~/.config/volens/lang)."

  # The user-facing notice follows the injection: if we inject, we say so; if the
  # user sees nothing, nothing was injected. systemMessage is a TOP-LEVEL field —
  # nested inside hookSpecificOutput it is silently ignored, and Claude Code logs
  # only "unrecognized keys (ignored)". Both Stop and SessionStart render it; the
  # earlier claim that SessionStart ignores it was never true and was never
  # testable while the placement was wrong. (Verified 2026-09-14 against Claude
  # Code's own session record: a payload carrying both placements produced a
  # single `hook_system_message` attachment, from the top-level key.)
  # A pin that exists but holds no language tag is ignored, not obeyed — and an
  # ignored pin is otherwise indistinguishable from one that worked, so the
  # notice that is about to be printed says which language is actually in force.
  # Only ever appended when we are already speaking, which keeps the rule that
  # silence means nothing was injected.
  local NOTE=""
  if [ -n "$LANG_PIN_IGNORED" ]; then
    if [ "$LANG_UI" = "zh" ]; then
      NOTE="（内容语言 pin 被忽略：不是语言标签，改用 ${LANG_DOC}）"
    else
      NOTE=" (content-language pin ignored — not a language tag; using ${LANG_DOC})"
    fi
  fi
  local MSG
  if [ "$LANG_UI" = "zh" ]; then
    if [ "$1" = "reset" ]; then
      MSG="📝 DECISION-LOG 被改写,光标已重置,将重建 DESIGN.md${NOTE}"
    else
      MSG="📝 DECISION-LOG 新增 ${N}→${M} 行,如意将同步 DESIGN.md${NOTE}"
    fi
  else
    if [ "$1" = "reset" ]; then
      MSG="📝 DECISION-LOG was rewritten; cursor reset, DESIGN.md will rebuild${NOTE}"
    else
      MSG="📝 DECISION-LOG grew (${N}→${M}); volens will sync DESIGN.md${NOTE}"
    fi
  fi
  # Every interpolated value is escaped: CONTEXT embeds this project's content
  # language, which comes from a file the project owns.
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
    "$(json_escape "$MSG")" "$(json_escape "$EVENT")" "$(json_escape "$CONTEXT")"
}

if [ "$M" -lt "$N" ]; then
  # Log was rewritten/rolled back: reset the cursor, then rebuild from zero. STALE
  # keeps the pre-reset count, which is what the message reports as the snapshot's
  # out-of-date position; N becomes the rebuild's starting point.
  STALE="$N"
  echo 0 > "$CURSOR"; N=0
  emit reset "$STALE"
elif [ -f "$DESIGN" ] && [ ! "$LOG" -nt "$DESIGN" ]; then
  # DESIGN already covers the log: fast-forward cursor, silent.
  echo "$M" > "$CURSOR"
elif [ "$N" -lt "$M" ]; then
  # New log lines: inject the delta. Cursor stays until regeneration confirms.
  emit sync
fi

exit 0
