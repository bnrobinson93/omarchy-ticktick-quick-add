import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
// Bare `Color` can resolve to the wrong type, so ReminderFlow.qml aliases it too.
import qs.Commons as Commons
import qs.Ui
import "Grammar.js" as Grammar

// A TickTick task prompt, parked near the top of the screen.
//
// `omarchy-menu-input` already does free-text capture, but the menu card is
// centered by a hardcoded `centeredTop` (plugins/menu/Menu.qml) with no setting
// behind it, and the layer surface covers the whole screen so no Hyprland layer
// rule can shift the card inside it. Moving the stock menu therefore means
// forking 1400 lines of Menu.qml that churn on every update. This is the small
// half instead: only the prompt moves, the SUPER menu stays exactly where
// Omarchy puts it.
//
// Summon with `omarchy-shell shell summon ticktick-quick-add`. The fields go to
// the `ticktask.sh` beside this file as `<title> <description> [subtask]...`.
//
// `keepLoaded` is what makes drafts work: closing only hides the window, so the
// fields keep their text and caret until a send succeeds or Esc clears them.
//
// The scrim and card come from plugins/reminders/ReminderFlow.qml. Remember that
// plugin QML is only re-instantiated by `omarchy restart shell`, not by a hot reload.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string activeField: "title"
  property bool sending: false
  property string sentDraft: ""
  readonly property string promptText: "New task  ·  *friday  ·  !high  ·  ~project  ·  #tag"
  readonly property string taskScript: Qt.resolvedUrl("ticktask.sh").toString().replace("file://", "")
  readonly property string fontFamily: Style.font.menuFamily

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(640), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(card.contentTopInset + card.contentBottomInset + Math.max(headerHeight, fields.implicitHeight), panel.height - Style.gapsOut * 2)

  // `ticktask.sh --refresh` rewrites these caches on every open; until it lands,
  // or when it fails, the last ones stand.
  readonly property string cacheDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/ticktask"
  readonly property var suggestData: ({ projects: parseCache(projectsFile.text()), tags: parseCache(tagsFile.text()) })
  property bool suggestDismissed: false
  property int suggestIndex: 0
  readonly property var suggestion: root.opened && root.activeField === "title" && !root.suggestDismissed
    ? Grammar.suggest(title.text, title.cursorPosition, root.suggestData) : null
  onSuggestionChanged: root.suggestIndex = 0

  function parseCache(text) {
    try { return JSON.parse(text) } catch (e) { return [] }
  }

  function pickSuggestion(index) {
    var s = root.suggestion
    var spaced = title.text.charAt(s.end) === " "
    title.replace(s.start, s.end + (spaced ? 1 : 0), s.items[index].insert + " ")
  }

  function open() {
    if (root.opened) {
      root.dismiss()
      return
    }
    root.opened = true
    if (!refresher.running) refresher.running = true
    Qt.callLater(focusActive)
  }

  function focusActive() {
    ({ title: title, description: description, subtasks: subtasks })[root.activeField].focusInput()
  }

  function moveTo(field) {
    root.activeField = field
    // A field can be hidden until activeField says otherwise.
    Qt.callLater(focusActive)
  }

  function draft() {
    return JSON.stringify([title.text, description.text, subtasks.text])
  }

  function clear() {
    title.text = description.text = subtasks.text = ""
    root.moveTo("title")
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "ticktick-quick-add")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open()
  }

  function handleKey(event) {
    var order = ["title", "description", "subtasks"]
    var at = order.indexOf(root.activeField)
    var isReturn = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
    var shift = event.modifiers & Qt.ShiftModifier
    var s = root.suggestion

    // An open list owns these keys. Every Return picks, so a half-typed `~wo` is never sent.
    if (s && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
      var step = event.key === Qt.Key_Down ? 1 : -1
      root.suggestIndex = (root.suggestIndex + step + s.items.length) % s.items.length
    } else if (s && (isReturn || (event.key === Qt.Key_Tab && !shift))) {
      root.pickSuggestion(root.suggestIndex)
    } else if (s && event.key === Qt.Key_Escape) {
      root.suggestDismissed = true
    } else if (event.key === Qt.Key_Escape) {
      if (title.text || description.text || subtasks.text) root.clear()
      else root.dismiss()
    } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && shift)) {
      if (at > 0) root.moveTo(order[at - 1])
    } else if (event.key === Qt.Key_Tab) {
      if (at < 2) root.moveTo(order[at + 1])
    } else if (isReturn && shift) {
      if (at < 2) root.moveTo(order[at + 1])
      else subtasks.insertNewline()
    } else if (isReturn && (event.modifiers & Qt.ControlModifier)) {
      if (root.activeField === "description") description.insertNewline()
    } else if (isReturn) {
      root.submit()
    } else {
      return
    }
    event.accepted = true
  }

  function submit() {
    if (root.sending) return
    var text = title.text.trim()
    root.dismiss()
    if (!text) return
    var items = subtasks.text.split("\n").map(function(s) { return s.trim() }).filter(Boolean)
    root.sentDraft = root.draft()
    root.sending = true
    // A login shell because `jq` and `op` can live on a PATH the shell never saw.
    sender.command = ["bash", "-lc", 'exec "$0" "$@"', root.taskScript, text, description.text.trim()].concat(items)
    sender.running = true
  }

  Process {
    id: sender
    onExited: function(exitCode, exitStatus) {
      root.sending = false
      if (exitCode !== 0 || exitStatus !== 0)
        Quickshell.execDetached(["notify-send", "TickTick task not sent", "Your draft is kept. Reopen quick add to retry."])
      else if (root.draft() === root.sentDraft)
        root.clear()
    }
  }

  Process {
    id: refresher
    command: ["bash", "-lc", 'exec "$0" "$@"', root.taskScript, "--refresh"]
    onExited: {
      projectsFile.reload()
      tagsFile.reload()
    }
  }

  FileView {
    id: projectsFile
    path: root.cacheDir + "/projects.json"
    printErrors: false
  }

  FileView {
    id: tagsFile
    path: root.cacheDir + "/tags.json"
    printErrors: false
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "ticktick-quick-add"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      // The spotlight line: high enough to read as "top of screen", low enough
      // to clear the bar and to sit where the eye already is.
      y: Math.max(Style.gapsOut, Math.round(panel.height * 0.15))
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Column {
          id: fields
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.controlPaddingY

          Field {
            id: title
            width: parent.width
            height: implicitHeight
            singleLine: true
            tokens: Grammar.title
            placeholder: root.promptText + "..."
            keyHandler: root.handleKey
            onFocused: root.activeField = "title"
            onTextChanged: root.suggestDismissed = false
            foreground: root.foreground
            accent: Commons.Color.accent
            tint: Util.alpha(Commons.Color.accent, 0.2)
            selection: Util.alpha(root.foreground, 0.25)
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Field {
            id: description
            width: parent.width
            height: implicitHeight
            visible: text || root.activeField === "description"
            wrap: true
            // Eight lines between the two fields, and neither squeezed below four.
            maxLines: Math.max(4, 8 - subtasks.lineCount)
            placeholder: "Description"
            keyHandler: root.handleKey
            onFocused: root.activeField = "description"
            foreground: root.foreground
            selection: Util.alpha(root.foreground, 0.25)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Field {
            id: subtasks
            width: parent.width
            height: implicitHeight
            visible: text || root.activeField === "subtasks"
            maxLines: Math.max(4, 8 - description.lineCount)
            tokens: Grammar.subtasks
            placeholder: "Subtasks"
            keyHandler: root.handleKey
            onFocused: root.activeField = "subtasks"
            foreground: root.foreground
            accent: Commons.Color.accent
            tint: Util.alpha(Commons.Color.accent, 0.2)
            selection: Util.alpha(root.foreground, 0.25)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        // Floats over the fields below, and past the card when they're hidden.
        Rectangle {
          id: suggestions
          visible: !!root.suggestion
          z: 1
          width: Math.min(parent.width, Style.space(320))
          height: list.implicitHeight + list.y * 2
          x: root.suggestion ? Math.max(0, Math.min(title.xAt(root.suggestion.start), parent.width - width)) : 0
          y: fields.y + title.height + Style.spacing.controlPaddingY
          radius: root.cornerRadius
          color: root.background
          border.color: root.border
          border.width: Style.spacing.hairline

          Column {
            id: list
            x: Style.spacing.controlPaddingY
            y: x
            width: parent.width - x * 2

            Repeater {
              model: root.suggestion ? root.suggestion.items : []

              Rectangle {
                required property var modelData
                required property int index
                readonly property bool selected: index === root.suggestIndex
                width: list.width
                height: label.implicitHeight + Style.spacing.controlPaddingY * 2
                radius: root.cornerRadius
                color: selected ? Commons.Color.menu.selectedBackground : "transparent"

                Text {
                  id: label
                  anchors.verticalCenter: parent.verticalCenter
                  x: Style.spacing.controlPaddingX
                  width: parent.width - x * 2
                  text: parent.modelData.label
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: parent.selected ? Commons.Color.menu.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.pickSuggestion(parent.index)
                }
              }
            }
          }
        }
      }
    }
  }
}
