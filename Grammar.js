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
