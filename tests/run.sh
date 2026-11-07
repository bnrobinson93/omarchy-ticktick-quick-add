#!/bin/bash
# Offline: a stub `curl` records each payload instead of sending it. Needs node and jq.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/data/ticktask" "$tmp/api"
printf 'fake-token' >"$tmp/data/ticktask/token"
printf '[{"id":"p-work","name":"Work"},{"id":"p-wl","name":"🎁 Wish List"},{"id":"p-wish","name":"Wish"},{"id":"p-old","name":"Old Work","closed":true}]' \
  >"$tmp/data/ticktask/projects.json"

# GETs answer with $tmp/api/<last URL segment>.
cat >"$tmp/bin/curl" <<STUB
#!/bin/bash
[ -e "$tmp/fail" ] && { echo "stub failure"; exit 22; }
while [ \$# -gt 0 ]; do
  [ "\$1" = "--data" ] && printf '%s' "\$2" >"$tmp/sent"
  url=\$1
  shift
done
[ -f "$tmp/api/\${url##*/}" ] && cat "$tmp/api/\${url##*/}"
true
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

send 'Plain #home' 'Multi
line "notes"'
check 'description alone goes in content, tags in tags' \
  '.content == "Multi\nline \"notes\"" and (has("desc") | not) and (has("kind") | not) and .tags == ["home"]'

send 'Trip *tomorrow 3pm !high ~work #a #b' 'Notes' 'Pack' 'Book #x !low *tomorrow 9am'
check 'description moves to desc once there are subtasks' \
  '.desc == "Notes" and (has("content") | not) and .kind == "CHECKLIST"'
check 'title tokens all land' \
  '.title == "Trip" and .priority == 5 and .projectId == "p-work" and .tags == ["a", "b"] and (.dueDate | test("T15:00:00[-+][0-9]{4}$"))'
check 'subtasks parse dates only, other markers stay as text' \
  '.items[0] == {title: "Pack", status: 0}
   and .items[1].title == "Book #x !low" and (.items[1].startDate | test("T09:00:00[-+][0-9]{4}$"))'

send 'No description' '' 'Only a subtask'
check 'empty description is left out' '(has("desc") | not) and (has("content") | not) and (.items | length) == 1'

send 'Gift ideas ~wish-list'
check 'emoji project names match by slug' '.title == "Gift ideas" and .projectId == "p-wl"'
send 'Buy ~wish'
check 'an exact slug beats a longer one that contains it' '.projectId == "p-wish"'
send 'Dig ~old-work'
check 'archived projects never match' '.title == "Dig ~old-work" and (has("projectId") | not)'

# Suggestions: the overlay offers `~<slug>` and must find the same project the script does.
node -e '
  const vm = require("vm"), fs = require("fs"), assert = require("assert");
  const g = {};
  vm.runInNewContext(fs.readFileSync(process.argv[1] + "/Grammar.js", "utf8").replace(".pragma library", ""), g);
  const data = {
    projects: JSON.parse(fs.readFileSync(process.argv[2], "utf8")).concat([{ name: "🎉" }]),
    tags: [{ name: "errand", label: "Errand" }, { name: "deep_work", label: "Deep Work" }],
  };
  const at = (text, caret = text.length) => {
    const s = JSON.parse(JSON.stringify(g.suggest(text, caret, data))); // out of the vm realm
    return s && { start: s.start, end: s.end, items: s.items.map(i => i.label + "=" + i.insert) };
  };
  assert.deepStrictEqual(at("Buy ~wi"), { start: 4, end: 7, items: ["🎁 Wish List=~wish-list", "Wish=~wish"] });
  assert.deepStrictEqual(at("~", 1).items, ["Work=~work", "🎁 Wish List=~wish-list", "Wish=~wish"], "all-emoji and archived projects are skipped");
  assert.deepStrictEqual(at("Buy ~wish").items, ["Wish=~wish", "🎁 Wish List=~wish-list"], "an exact slug comes first, as in the script");
  assert.deepStrictEqual(at("a !m").items, ["medium=!medium"]);
  assert.deepStrictEqual(at("a #deep").items, ["Deep Work=#deep_work"], "tags show label, insert name");
  assert.deepStrictEqual(at("a #wor x", 4), { start: 2, end: 6, items: ["Deep Work=#deep_work"] }, "caret mid-token spans the word");
  assert.strictEqual(at("a ~work"), null, "a finished token closes the list");
  assert.strictEqual(at("x!hi"), null, "only after a space");
  assert.strictEqual(at("a ~wish b"), null, "caret not in a token");
  assert.strictEqual(at("a ~zzz"), null);
' "$root" "$tmp/data/ticktask/projects.json"
echo 'ok: suggestions'

printf '[{"id":"p-new","name":"New"}]' >"$tmp/api/project"
printf '[{"name":"errand","label":"Errand"}]' >"$tmp/api/tag"
send --refresh
jq -e '.[0].id == "p-new"' "$tmp/data/ticktask/projects.json" >/dev/null &&
  jq -e '.[0].name == "errand"' "$tmp/data/ticktask/tags.json" >/dev/null ||
  { echo 'FAIL: --refresh did not cache projects and tags'; exit 1; }
echo 'ok: --refresh caches projects and tags'

touch "$tmp/fail"
if send --refresh; then echo 'FAIL: failed refresh exited 0'; exit 1; fi
jq -e '.[0].id == "p-new"' "$tmp/data/ticktask/projects.json" >/dev/null &&
  jq -e '.[0].name == "errand"' "$tmp/data/ticktask/tags.json" >/dev/null ||
  { echo 'FAIL: failed refresh clobbered the cache'; exit 1; }
echo 'ok: failed refresh keeps the last cache'

if send 'Lost? "no"' 'Details here' 'Sub one'; then echo 'FAIL: failed send exited 0'; exit 1; fi
eval "spooled=($(cat "$tmp"/data/ticktask/error_tasks/*))"
[ "${spooled[*]}" = 'Lost? "no" Details here Sub one' ] && [ "${#spooled[@]}" -eq 3 ] \
  || { echo "FAIL: spool lost the structure: ${spooled[*]}"; exit 1; }
echo 'ok: failed send exits non-zero and spools every field'
