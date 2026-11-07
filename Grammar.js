.pragma library

// The token rules from ticktask.sh, for coloring only. tests/run.sh fails if the
// two disagree. `first` mirrors the script, which honors only the first of a kind.
// Group 1 is the separator before a token, and is not part of the token.
var date = { re: /(^| )\*[a-zA-Z0-9_-]+( [0-9]{1,2}(:[0-9]{2})?[aApP][mM])?(?= |$)/g, first: true }
var priority = { re: /(^| )!(high|medium|low)(?= |$)/g, first: true }
var project = { re: /(^| )~[a-zA-Z0-9_-]+(?= |$)/g, first: true }
var tag = { re: /(^| )#[a-zA-Z0-9_]+(?= |$)/g, first: false }

function ranges(line, rules) {
  var found = []
  rules.forEach(function(rule) {
    rule.re.lastIndex = 0
    var m
    while ((m = rule.re.exec(line))) {
      found.push([m.index + m[1].length, m.index + m[0].length])
      if (rule.first) break
    }
  })
  return found.sort(function(a, b) { return a[0] - b[0] })
}

// Splits text into { start, text, token } pieces, one or more per line. `start`
// is the offset into the whole text, so a piece can find its own pixel position.
function segments(text, rules) {
  var pieces = []
  var offset = 0
  text.split("\n").forEach(function(line) {
    var at = 0
    ranges(line, rules).forEach(function(r) {
      if (r[0] > at) pieces.push({ start: offset + at, text: line.slice(at, r[0]), token: false })
      pieces.push({ start: offset + r[0], text: line.slice(r[0], r[1]), token: true })
      at = r[1]
    })
    if (at < line.length) pieces.push({ start: offset + at, text: line.slice(at), token: false })
    offset += line.length + 1
  })
  return pieces
}

function title(text) { return segments(text, [date, priority, project, tag]) }
function subtasks(text) { return segments(text, [date]) }

// "🚀 Side Projects" -> "side-projects". ticktask.sh has the same rule in jq.
function slug(name) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
}

// The completions for the token the caret is in, or null. `data` is
// { projects: [{name}], tags: [{name, label}] } straight from the API caches.
// Returns { start, end, items: [{ label, insert }] }, where start..end is the
// whole word to replace, trigger included.
function suggest(text, caret, data) {
  var m = /(^| )([~!#])([^ ]*)$/.exec(text.slice(0, caret))
  if (!m) return null
  var start = m.index + m[1].length
  var end = caret + /^[^ ]*/.exec(text.slice(caret))[0].length
  var query = m[3].toLowerCase()
  var options = {
    "!": ["high", "medium", "low"].map(function(p) { return { label: p, insert: "!" + p } }),
    "~": (data.projects || []).filter(function(p) { return !p.closed && slug(p.name) }).map(function(p) {
      return { label: p.name, insert: "~" + slug(p.name) }
    }),
    "#": (data.tags || []).map(function(t) { return { label: t.label || t.name, insert: "#" + t.name } }),
  }[m[2]]
  var word = text.slice(start, end)
  var items = options.filter(function(o) {
    return o.insert.slice(1).indexOf(query) !== -1 || o.label.toLowerCase().indexOf(query) !== -1
  })
  // Exact first, as ticktask.sh resolves it, so Enter on a finished `~wish` keeps it.
  items = items.filter(function(o) { return o.insert === word })
    .concat(items.filter(function(o) { return o.insert !== word })).slice(0, 6)
  // Nothing left to pick once the word already is the only match.
  if (!items.length || (items.length === 1 && items[0].insert === word)) return null
  return { start: start, end: end, items: items }
}
