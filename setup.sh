#!/usr/bin/env bash
# setup.sh — provider, key, model. No LLM involved, because at this point there is nothing to talk to.
#
# The interview cannot run before a model exists: an interviewer is an agent. So this is a plain script,
# and it is the only place a credential is ever typed. Nothing here prints, logs or echoes a key.
#
# Usage:
#   ./setup.sh            # ask, verify, write
#   ./setup.sh --check    # report what is already configured (no writes, safe to run anytime)
#
# Writes: $HERMES_HOME/.env and $HERMES_HOME/profiles/guide/.env (key), and model.provider /
# model.default in both profiles' config. The guide inherits the same model by design.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
GUIDE_PROFILE="${GUIDE_PROFILE:-guide}"
MODE="run"
[ "${1:-}" = "--check" ] && MODE="check"

say() { printf '\n%s\n' "$*"; }
ok()  { printf '  ✓ %s\n' "$*"; }
bad() { printf '  ✗ %s\n' "$*" >&2; }

# ── current state ────────────────────────────────────────────────────────────
keyname_for() {  # provider -> the env var that carries it
  case "$1" in
    openrouter) echo OPENROUTER_API_KEY ;;
    openai)     echo OPENAI_API_KEY ;;
    anthropic)  echo ANTHROPIC_API_KEY ;;
    google)     echo GOOGLE_API_KEY ;;
    *)          echo "" ;;
  esac
}

src_has_key() {  # file keyname -> true when that exact name has a value
  [ -n "$2" ] && [ -f "$1" ] && grep -qE "^$2=.+" "$1" 2>/dev/null
}

report_status() {
  local provider model keyname
  provider="$(hermes -p default config get model.provider 2>/dev/null | head -1)"
  model="$(hermes -p default config get model.default 2>/dev/null | head -1)"
  keyname="$(keyname_for "$provider")"
  say "Current state"
  printf '  provider : %s\n' "${provider:-<unset>}"
  printf '  model    : %s\n' "${model:-<unset>}"
  if [ "$provider" = "local" ]; then
    printf '  key      : not required (local endpoint)\n'
  elif src_has_key "$HERMES_HOME/.env" "$keyname"; then
    printf '  key      : %s is set (%s/.env)\n' "$keyname" "$HERMES_HOME"
  else
    printf '  key      : %s is NOT set — the model cannot answer\n' "${keyname:-<provider unknown>}"
  fi
  if src_has_key "$HERMES_HOME/profiles/$GUIDE_PROFILE/.env" "$keyname" || src_has_key "$HERMES_HOME/.env" "$keyname"; then
    printf '  guide    : can reach the model\n'
  else
    printf '  guide    : <no key — the interview cannot start>\n'
  fi
}

if [ "$MODE" = "check" ]; then
  report_status
  exit 0
fi

# ── preconditions ────────────────────────────────────────────────────────────
if [ ! -t 0 ]; then
  bad "not a terminal — this needs hidden input for the key. Run it interactively."
  exit 2
fi
if ! command -v curl >/dev/null 2>&1; then
  bad "curl is required to verify the key before trusting it."
  exit 2
fi

CONF_PROVIDER="$(hermes -p default config get model.provider 2>/dev/null | head -1)"
CONF_KEY="$(keyname_for "$CONF_PROVIDER")"
if src_has_key "$HERMES_HOME/.env" "$CONF_KEY" \
   && src_has_key "$HERMES_HOME/profiles/$GUIDE_PROFILE/.env" "$CONF_KEY" \
   && [ -n "$(hermes -p default config get model.default 2>/dev/null | head -1)" ] \
   && [ "${FORCE:-0}" != "1" ]; then
  report_status
  printf '\n  Already configured. Re-run with FORCE=1 ./setup.sh to change it.\n'
  exit 0
fi

say "Which provider?"
cat <<'MENU'
  1) OpenRouter     (one key, most models, pay-as-you-go)
  2) OpenAI
  3) Anthropic
  4) Google Gemini
  5) A local endpoint (Ollama, llama.cpp, LM Studio, vLLM)
MENU
printf '\n  choice [1]: '
read -r CHOICE
CHOICE="${CHOICE:-1}"

case "$CHOICE" in
  1) PROVIDER="openrouter"; KEYNAME="OPENROUTER_API_KEY"; VALIDATE="openrouter";;
  2) PROVIDER="openai";     KEYNAME="OPENAI_API_KEY";     VALIDATE="openai";;
  3) PROVIDER="anthropic";  KEYNAME="ANTHROPIC_API_KEY";  VALIDATE="anthropic";;
  4) PROVIDER="google";     KEYNAME="GOOGLE_API_KEY";     VALIDATE="google";;
  5) PROVIDER="local";      KEYNAME="";                   VALIDATE="local";;
  *) bad "unknown choice: $CHOICE"; exit 2;;
esac

if [ "$PROVIDER" = "local" ]; then
  printf '  Base URL [http://localhost:11434/v1]: '
  read -r BASE_URL
  BASE_URL="${BASE_URL:-http://localhost:11434/v1}"
  KEY=""
else
  printf '  Paste your %s key (input hidden, never echoed): ' "$PROVIDER"
  read -rs KEY
  printf '\n'
  if [ -z "$KEY" ]; then bad "no key entered"; exit 2; fi
fi

# ── verify before writing anything ───────────────────────────────────────────
# A wrong key must fail HERE, in second twenty, not two hundred lines into an interview.
say "Verifying the key with one live call…"
case "$VALIDATE" in
  openrouter) code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 \
                 -H "Authorization: Bearer $KEY" https://openrouter.ai/api/v1/key)";;
  openai)     code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 \
                 -H "Authorization: Bearer $KEY" https://api.openai.com/v1/models)";;
  anthropic)  code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 \
                 -H "x-api-key: $KEY" -H "anthropic-version: 2023-06-01" \
                 https://api.anthropic.com/v1/models)";;
  google)     code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 \
                 "https://generativelanguage.googleapis.com/v1beta/models?key=$KEY")";;
  local)      code="$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$BASE_URL/models")";;
esac

if [ "${code:0:1}" != "2" ]; then
  bad "the provider answered HTTP $code — the key was not accepted. Nothing was written."
  exit 1
fi
ok "key accepted (HTTP $code)"

# ── choose a model, from the provider's own list ─────────────────────────────
say "Available models (first 15) — pick a number or paste an id:"
case "$VALIDATE" in
  openrouter) LIST_URL="https://openrouter.ai/api/v1/models"; AUTH=(-H "Authorization: Bearer $KEY");;
  openai)     LIST_URL="https://api.openai.com/v1/models";    AUTH=(-H "Authorization: Bearer $KEY");;
  anthropic)  LIST_URL="https://api.anthropic.com/v1/models"; AUTH=(-H "x-api-key: $KEY" -H "anthropic-version: 2023-06-01");;
  google)     LIST_URL="https://generativelanguage.googleapis.com/v1beta/models?key=$KEY"; AUTH=();;
  local)      LIST_URL="$BASE_URL/models"; AUTH=();;
esac

MODELS="$(curl -s -m 25 "${AUTH[@]}" "$LIST_URL" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
items = d.get("data") if isinstance(d,dict) and isinstance(d.get("data"),list) else (
        d.get("models") if isinstance(d,dict) and isinstance(d.get("models"),list) else [])
ids=[]
for m in items:
    if not isinstance(m,dict): continue
    i=m.get("id") or m.get("name")
    if i: ids.append(i)
for n,i in enumerate(ids[:15],1): print(f"{n}\t{i}")
' 2>/dev/null)"

if [ -n "$MODELS" ]; then
  while IFS=$'\t' read -r n mid; do printf '   %2s) %s\n' "$n" "$mid"; done <<<"$MODELS"
  printf '\n  number or model id: '
  read -r PICK
  MODEL="$(printf '%s\n' "$MODELS" | awk -F'\t' -v p="$PICK" '$1==p{print $2}')"
  [ -z "$MODEL" ] && MODEL="$PICK"
else
  printf '  (could not list models — paste an id)\n  model id: '
  read -r MODEL
fi
[ -z "$MODEL" ] && { bad "no model chosen"; exit 2; }
ok "model: $MODEL"

# ── write: key to .env (mode 600), model to config ───────────────────────────
write_key() {  # file keyname value-on-stdin
  local file="$1" name="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"; chmod 600 "$file"
  python3 - "$file" "$name" <<'PY'
import sys, pathlib
# value arrives on stdin: never in argv (ps), never echoed, never logged.
p, name = sys.argv[1], sys.argv[2]
val = sys.stdin.read().strip()
lines = pathlib.Path(p).read_text().splitlines() if pathlib.Path(p).exists() else []
out, done = [], False
for ln in lines:
    if ln.startswith(name + "="):
        out.append(f"{name}={val}"); done = True
    else:
        out.append(ln)
if not done:
    out.append(f"{name}={val}")
pathlib.Path(p).write_text("\n".join(out) + "\n")
PY
}

if [ -n "$KEYNAME" ]; then
  printf '%s' "$KEY" | write_key "$HERMES_HOME/.env" "$KEYNAME"
  printf '%s' "$KEY" | write_key "$HERMES_HOME/profiles/$GUIDE_PROFILE/.env" "$KEYNAME"
  ok "key written to .env and profiles/$GUIDE_PROFILE/.env (mode 600)"
fi

for prof in default "$GUIDE_PROFILE"; do
  # always explicit: an unscoped `hermes` resolves the profile from $HERMES_HOME
  hermes -p "$prof" config set model.provider "$PROVIDER" >/dev/null 2>&1 || true
  hermes -p "$prof" config set model.default "$MODEL"     >/dev/null 2>&1 || true
  [ "$PROVIDER" = "local" ] && hermes -p "$prof" config set model.base_url "$BASE_URL" >/dev/null 2>&1 || true
done
unset KEY
ok "model set for default and $GUIDE_PROFILE"

say "Done — a model is reachable, so the conversation can start."
printf '  Next: ./bootstrap.sh   (then the guide takes over)\n'
