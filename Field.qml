import QtQuick

// A text input that can color parts of its own text. TextEdit can't do that in
// plain text, so with `tokens` set its glyphs go transparent and a Text per piece
// is laid over each one, positioned by the TextEdit's own layout. It keeps the
// caret, selection and clipboard, and nothing needs HTML escaping.
Flickable {
  id: root

  property alias text: edit.text
  property alias font: edit.font
  property var tokens: null
  property var keyHandler: null
  property color foreground: "white"
  property color accent: "white"
  property color tint: "transparent"
  property color selection: "gray"

  function focusInput() { edit.forceActiveFocus() }

  implicitHeight: edit.implicitHeight
  contentWidth: edit.width
  contentHeight: edit.implicitHeight
  clip: true
  interactive: false
  boundsBehavior: Flickable.StopAtBounds

  TextEdit {
    id: edit
    width: Math.max(root.width, implicitWidth)
    textFormat: TextEdit.PlainText
    color: root.tokens ? "transparent" : root.foreground
    selectedTextColor: color
    selectionColor: root.selection
    selectByMouse: true
    // The default caret takes the text color, which is transparent here.
    cursorDelegate: Rectangle {
      width: 2
      z: 1
      color: root.foreground
      visible: edit.cursorVisible
    }

    Keys.onPressed: function(event) {
      if (root.keyHandler) root.keyHandler(event)
    }

    onCursorRectangleChanged: {
      var r = cursorRectangle
      if (root.contentX > r.x) root.contentX = r.x
      else if (root.contentX + root.width < r.x + r.width) root.contentX = r.x + r.width - root.width
      if (root.contentY > r.y) root.contentY = r.y
      else if (root.contentY + root.height < r.y + r.height) root.contentY = r.y + r.height - root.height
    }

    Repeater {
      model: root.tokens ? root.tokens(edit.text) : []

      Rectangle {
        required property var modelData
        // positionToRectangle() has no dependencies of its own, and the first
        // call can run before layout. contentWidth changes once layout is done.
        readonly property rect at: {
          edit.contentWidth
          return edit.positionToRectangle(modelData.start)
        }
        x: at.x
        y: at.y
        width: label.implicitWidth
        height: at.height
        radius: 3
        color: modelData.token ? root.tint : "transparent"

        Text {
          id: label
          text: parent.modelData.text
          textFormat: Text.PlainText
          color: parent.modelData.token ? root.accent : root.foreground
          font: edit.font
        }
      }
    }
  }
}
