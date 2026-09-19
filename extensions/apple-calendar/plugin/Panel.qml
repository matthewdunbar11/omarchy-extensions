import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "CalendarModel.js" as Cal

// Apple Calendar popup: a month grid dotted with iCloud event days, and the
// selected day's events listed along the bottom. Data arrives via the sync
// script's JSON cache (see ../../sync/cal_sync.py), watched live.
//
// Click a day to select it (dots mark days with events); the hero is the way
// home — clicking it jumps back to today. Chevrons step months, the circular
// arrow triggers a background sync.
Panel {
  id: root
  moduleName: "omx.apple-calendar"
  ipcTarget: "omx.apple-calendar"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today / viewed month / selected day.
  property date today: new Date()
  readonly property string todayKey: Cal.keyForDate(today)

  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  property string selectedKey: todayKey
  readonly property var selectedEvents: Cal.eventsForDay(root.eventDays, root.selectedKey)

  // ---- iCloud event cache (written by cal_sync.py, see sync/).
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string cachePath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/omx/apple-calendar/events.json"

  property var eventDays: ({})
  property bool cacheReady: false
  property string syncedAt: ""

  function parseCache(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      if (parsed && typeof parsed === "object" && parsed.days && typeof parsed.days === "object") {
        root.eventDays = parsed.days
        root.syncedAt = String(parsed.synced_at || "")
        root.cacheReady = true
        return
      }
    } catch (e) { /* fall through to not-ready */ }
    root.eventDays = ({})
    root.cacheReady = false
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseCache(text())
    onLoadFailed: root.parseCache(null)
  }

  // Refresh = run the systemd sync service; the FileView above picks up the
  // rewritten cache when it lands. No credentials in this process.
  Process {
    id: syncProcess
    running: false
    command: ["systemctl", "--user", "start", "omx-apple-calendar-sync.service"]
  }

  // ---- Week start follows the locale, same convention as the stock clock.
  readonly property int weekStart: Cal.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property string nextWeekStartLabel: Qt.locale("en_US").dayName(weekStart === 1 ? 0 : 1, Locale.LongFormat)
  readonly property var weekdays: Cal.weekdayOrder(weekStart)
  readonly property var weeks: Cal.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(38)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  // Fixed grid width (gutter + 7 day cells + 8 gaps): every consumer uses
  // this instead of measuring children, so no width binding can loop.
  readonly property int gridWidth: weekColumnWidth + gutterWidth + 7 * cellWidth + 8 * cellSpacing

  function open() {
    refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    root.today = new Date()
    root.selectedKey = root.todayKey
    root.goToToday()
    cacheFile.reload()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
    root.selectedKey = root.todayKey
  }

  function moveMonth(delta) {
    var next = Cal.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function weekdayLabel(weekday) {
    return String(Qt.locale("en_US").dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  function selectedLabel() {
    if (root.selectedKey === root.todayKey) return "Today"
    var parts = root.selectedKey.split("-")
    if (parts.length !== 3) return root.selectedKey
    var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    return Qt.formatDate(d, "dddd, MMMM d")
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Cal.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      root.selectedKey = root.todayKey
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveMonth(dy * 12)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "r" || t === "R") { if (!syncProcess.running) syncProcess.running = true }
      }

      Flickable {
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          width: Math.max(parent.width, root.gridWidth)
          spacing: Style.space(8)

          // ---- Hero: the selected day. Clicking goes home to today.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: root.selectedLabel() === "Today"
                  ? Qt.formatDate(root.today, "MMMM d")
                  : root.selectedLabel()
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 44
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: root.selectedKey !== root.todayKey || !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Month grid with event dots.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              width: root.gridWidth
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                spacing: root.cellSpacing

                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  color: "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: root.viewingCurrentMonth ? "•" : "‹"
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: ""
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      required property var modelData

                      readonly property bool isSelected: modelData.key === root.selectedKey
                      readonly property bool busy: Cal.hasEvents(root.eventDays, modelData.key)

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      color: isSelected
                        ? Style.selectedStateColor(root.contentForeground, Color.accent)
                        : "transparent"
                      border.width: modelData.today && !isSelected ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      Text {
                        textFormat: Text.PlainText
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Style.space(5)
                        text: modelData.day
                        color: parent.isSelected
                          ? Style.hoverStateColor(root.contentForeground, Color.accent)
                          : (modelData.inMonth
                            ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                            : Qt.darker(root.contentForeground, 2.2))
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.today
                      }

                      // Event dot: the whole point of this panel.
                      Rectangle {
                        visible: parent.busy
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(5)
                        width: Style.space(5)
                        height: Style.space(5)
                        radius: width / 2
                        color: parent.isSelected
                          ? Style.hoverStateColor(root.contentForeground, Color.accent)
                          : Style.selectedStateColor(root.contentForeground, Color.accent)
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedKey = modelData.key
                      }
                    }
                  }
                }
              }
            }
          }

          // ---- Month stepping + sync, one rail.
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(22)
                anchors.verticalCenter: parent.verticalCenter
                iconText: syncProcess.running ? "󰑓" : "󰑐"
                tooltipText: syncProcess.running ? "Syncing…" : "Sync iCloud now"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                enabled: !syncProcess.running
                onClicked: syncProcess.running = true
              }
            }
          }

          // ---- Selected day's events, along the bottom.
          Column {
            id: eventSection
            width: gridColumn.width
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)
            visible: root.cacheReady

            Text {
              textFormat: Text.PlainText
              text: root.selectedLabel().toUpperCase()
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            Repeater {
              model: root.selectedEvents

              Row {
                required property var modelData
                width: eventSection.width
                spacing: Style.space(10)

                Text {
                  textFormat: Text.PlainText
                  width: Style.space(96)
                  text: Cal.timeRangeText(modelData)
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Column {
                  width: parent.width - Style.space(106)
                  spacing: 0

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    elide: Text.ElideRight
                    text: modelData.title
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    textFormat: Text.PlainText
                    visible: modelData.calendar !== ""
                    width: parent.width
                    elide: Text.ElideRight
                    text: modelData.calendar
                    color: Qt.darker(root.contentForeground, 1.7)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            Text {
              visible: root.selectedEvents.length === 0
              textFormat: Text.PlainText
              text: "No events — enjoy the quiet."
              color: Qt.darker(root.contentForeground, 1.7)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }
          }

          // ---- No cache yet: point at setup, not an empty grid of lies.
          Text {
            visible: !root.cacheReady
            anchors.horizontalCenter: parent.horizontalCenter
            width: gridColumn.width
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: "No iCloud events yet — run cal_sync.py login, then sync."
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
