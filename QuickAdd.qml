import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Grammar.js" as Grammar

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
// Summon with `omarchy-shell shell summon ticktick-quick-add`. The typed line
// goes to the `ticktask.sh` beside this file as a single argument.
//
// Borrowed wholesale from plugins/reminders/ReminderFlow.qml: the same key
// catcher, the same scrim, the same card. Remember that plugin QML is only
// re-instantiated by `omarchy restart shell`, not by a hot reload.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  readonly property string promptText: "New task  ·  *friday  ·  !high  ·  ~project  ·  #tag"
  readonly property string taskScript: Qt.resolvedUrl("ticktask.sh").toString().replace("file://", "")
  readonly property string fontFamily: Style.font.menuFamily

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

  function open() {
    title.text = ""
    root.opened = true

    Qt.callLater(function() { title.focusInput() })
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
    if (event.key === Qt.Key_Escape) {
      if (title.text) title.text = ""
      else root.dismiss()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.submit()
      event.accepted = true
    }
  }

  function submit() {
    var text = title.text.trim()
    root.dismiss()
    if (!text) return
    // A login shell because `jq` and `op` can live on a PATH the shell never saw.
    Quickshell.execDetached(["bash", "-lc", 'exec "$0" "$@"', root.taskScript, text])
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

        Field {
          id: title
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: implicitHeight
          tokens: Grammar.title
          keyHandler: root.handleKey
          foreground: root.foreground
          accent: Color.accent
          tint: Util.alpha(Color.accent, 0.2)
          selection: Util.alpha(root.foreground, 0.25)
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }

        Text {
          anchors.fill: title
          visible: !title.text
          text: root.promptText + "..."
          color: root.foreground
          opacity: 0.58
          font: title.font
          elide: Text.ElideRight
        }
      }
    }
  }
}
