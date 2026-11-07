#!/bin/bash
# Offline: a stub `curl` records each payload instead of sending it. Needs node and jq.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/data/ticktask"
printf 'fake-token' >"$tmp/data/ticktask/token"
printf '[{"id":"p-work","name":"Work"}]' >"$tmp/data/ticktask/projects.json"

cat >"$tmp/bin/curl" <<STUB
#!/bin/bash
[ -e "$tmp/fail" ] && { echo "stub failure"; exit 22; }
while [ \$# -gt 0 ]; do
  [ "\$1" = "--data" ] && printf '%s' "\$2" >"$tmp/sent"
  shift
done
STUB
chmod +x "$tmp/bin/curl"

send() {
  XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:$PATH" \
    "$root/ticktask.sh" "$@" >/dev/null
}

check() { # label, jq filter that must be true
  jq -e "$2" "$tmp/sent" >/dev/null || { echo "FAIL: $1"; cat "$tmp/sent"; echo; exit 1; }
  echo "ok: $1"
}

# Grammar.js and ticktask.sh must agree on what is a token: what Grammar.js marks,
# the script strips. Markers that only fail at runtime (a bad date, an unknown
# project) are syntax-valid on purpose, so they aren't in this list.
lines=(
  'plain words'
  'a *friday b'
  '*today 9:30am a'
  'a *tomorrow 3pm'
  'a !high b'
  'x!high !urgent stays'
  'a !high !low b'
  'a ~work b'
  'a ~work b ~work'
  'a #t1 #t2 b'
  'a #b.c stays'
  '*friday !high ~work #t title'
  'say "hi" \there'
)
for line in "${lines[@]}"; do
  send "$line"
  sent=$(jq -r .title "$tmp/sent")
  expected=$(node -e '
    const vm = require("vm"), fs = require("fs");
    const g = {};
    vm.runInNewContext(fs.readFileSync(process.argv[1] + "/Grammar.js", "utf8").replace(".pragma library", ""), g);
    const kept = g.title(process.argv[2]).filter(p => !p.token).map(p => p.text).join("");
    console.log(kept.replace(/ +/g, " ").trim());
  ' "$root" "$line")
  [ "$sent" = "$expected" ] || { echo "FAIL: grammar drift on '$line': script '$sent', grammar '$expected'"; exit 1; }
  echo "ok: grammar agrees on '$line'"
done
