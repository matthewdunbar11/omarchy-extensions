import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Date/time label for the bar, hosting the Apple Calendar popup.
//
// Same shape contract as the stock clock widget so Bar.findPanelWidget
// routing works unchanged: open/close/opened on the bar-widget root, plus
// popout-switch forwarding. Left click toggles the calendar panel.
BarWidget {
  id: root
  moduleName: "omx.apple-calendar"

  property date displayDate: clock.date

  readonly property string configuredFormat: setting("format", "ddd d MMM h:mm AP")
  readonly property string displayText: Qt.formatDateTime(displayDate, configuredFormat)

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  function refresh() {
    displayDate = new Date()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "omx.apple-calendar"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: "Apple Calendar"

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.togglePanel()
    }
  }
}
