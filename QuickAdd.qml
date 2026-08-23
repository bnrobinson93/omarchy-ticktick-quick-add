import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// A one-line free-text prompt, parked near the top of the screen.
//
// `omarchy-menu-input` already does free-text capture, but the menu card is
// centered by a hardcoded `centeredTop` (plugins/menu/Menu.qml) with no setting
// behind it, and the layer surface covers the whole screen so no Hyprland layer
// rule can shift the card inside it. Moving the stock menu therefore means
// forking 1400 lines of Menu.qml that churn on every update. This is the small
// half instead: only the prompt moves, the SUPER menu stays exactly where
// Omarchy puts it.
//
// Generic on purpose — the payload carries the prompt and the command, and the
// typed line is passed to that command as a single argument:
//
//   omarchy-shell shell summon quick-add \
//     '{"prompt":"New task","exec":"ticktask.sh"}'
//
// Borrowed wholesale from plugins/reminders/ReminderFlow.qml: the same key
// catcher, the same scrim, the same card. Remember that plugin QML is only
// re-instantiated by `omarchy restart shell`, not by a hot reload.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string promptText: "Input"
  property string execCommand: ""
  property string filterText: ""
  property string fontFamily: Style.font.menuFamily

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(640), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(contentMargin * 2 + headerHeight, panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.promptText = String(payload.prompt || "Input")
    root.execCommand = String(payload.exec || "")
    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    root.filterText = ""
    root.opened = true

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "quick-add")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
  }

  function submit() {
    var text = root.filterText.trim()
    root.dismiss()
    if (!text || !root.execCommand) return
    // `"$1"` rather than interpolation: the task line carries quotes, `!`, and
    // `#` often enough that pasting it into the command string would be a
    // quoting bug waiting to happen.
    Quickshell.execDetached(["bash", "-lc", root.execCommand + ' "$1"', "bash", text])
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quick-add"
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
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit()
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.filterText || (root.promptText + "...")
          color: root.foreground
          opacity: root.filterText ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideRight
        }
      }
    }
  }
}
