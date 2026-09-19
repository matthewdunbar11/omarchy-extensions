import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "CalendarModel.js" as Cal

// Apple Calendar popup: the stock clock's calendar, wired to iCloud. Same
// hero-over-rail-over-grid composition, spacing scale, and small-caps labels,
// plus event dots on busy days and the selected day's agenda along the bottom.
//
// Unlike the clock's read-only grid this one is a picker: click a day to see
// its events. Today is outlined, the selected day is filled, and clicking the
// hero (the date) jumps back home.
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

  // Selected day as a real Date. Plain root-level properties (the stock-plugin
  // convention) — nested readonly aliases failed to resolve on the systems
  // tested.
  property var selParts: Cal.parseKey(selectedKey) || {
    year: today.getFullYear(), month: today.getMonth(), day: today.getDate()
  }
  property date selDate: new Date(selParts.year, selParts.month, selParts.day)
  readonly property bool viewingToday: selectedKey === todayKey

  // ---- iCloud event cache (written by cal_sync.py, see sync/).
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string cachePath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/omx/apple-calendar/events.json"

  property var eventDays: ({})
  property bool cacheReady: false
  property string syncedAt: ""
  property int calCount: 0

  function parseCache(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      if (parsed && typeof parsed === "object" && parsed.days && typeof parsed.days === "object") {
        root.eventDays = parsed.days
        root.syncedAt = String(parsed.synced_at || "")
        root.calCount = Number(parsed.calendars || 0)
        root.cacheReady = true
        return
      }
    } catch (e) { /* fall through to not-ready */ }
    root.eventDays = ({})
    root.cacheReady = false
  }

  function syncLine() {
    if (!root.cacheReady || root.syncedAt === "") return ""
    var when = new Date(root.syncedAt)
    var stamp = isFinite(when.getTime()) ? Qt.formatDateTime(when, "h:mm AP") : ""
    var cals = root.calCount > 0 ? " · " + root.calCount + (root.calCount === 1 ? " calendar" : " calendars") : ""
    return "Synced" + (stamp !== "" ? " " + stamp : "") + cals
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

  // ---- Week start follows the locale, same convention and toggle as the
  //      stock clock: clicking the grid's "W" heading writes the choice back
  //      to shell.json.
  readonly property int weekStart: Cal.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Cal.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Cal.weekdayOrder(weekStart)
  readonly property var weeks: Cal.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // Text laid on a filled (selected) cell has to invert to the popup surface.
  // The default theme resolves selection *and* its label to `foreground`, so
  // reusing the state color for both paints the selected date invisible.
  readonly property color onSelectedColor: Color.popups.background

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(38)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  // Fixed grid width (week column + gutter + 7 day cells + 8 gaps): every
  // consumer uses this instead of measuring children, so no width binding can
  // loop.
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

  // Applied locally first so the grid redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry it stays a session-only preference rather than doing
  // nothing.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Cal.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Cal.weekStartSettingName(next) })
  }

  function toggleWeekStart() {
    setWeekStart(Cal.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  // Left end of the rail: "TODAY" when you are home, else the weekday.
  function railLabel() {
    if (root.viewingToday) return "Today"
    return Qt.formatDate(root.selDate, "dddd")
  }

  function eventCountLabel() {
    var n = root.selectedEvents.length
    return n === 0 ? "No events" : (n === 1 ? "1 event" : n + " events")
  }

  // Sync can record an event with no clock time; keep the column from reading
  // as a rendering failure.
  function timeRange(ev) {
    var text = Cal.timeRangeText(ev)
    return text === "" ? "—" : text
  }

  function syncTooltip() {
    var line = root.syncLine()
    return line === "" ? "Sync iCloud now" : "Sync iCloud now · " + line
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
        else if (t === "{") root.moveMonth(-12)
        else if (t === "}") root.moveMonth(12)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
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
          // Anchored to the panel's FIXED content width, never to the
          // Flickable: measuring the viewport that measures us is what loops.
          width: Math.max(panel.contentWidth, root.gridWidth)
          spacing: Style.space(8)

          // ---- Hero: the selected day, in the clock's voice — a calendar
          //      glyph beside a large date. Once the selection has left today
          //      it is also the way home. Baseline-aligned, not center-aligned:
          //      the date carries a descender, so centering the two boxes
          //      leaves the glyph sitting visibly low.
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
                text: Qt.formatDate(root.selDate, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingToday || !root.viewingCurrentMonth
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

          // ---- Rail under the hero, like the clock's year meter: what day is
          //      selected on the left, how full it is on the right.
          Item {
            width: parent.width
            height: rail.height

            Item {
              id: rail
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(railLabelText.implicitHeight, eventCountText.implicitHeight)

              Text {
                id: railLabelText
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.railLabel().toUpperCase()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
              }

              Text {
                id: eventCountText
                textFormat: Text.PlainText
                visible: root.cacheReady
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.eventCountLabel().toUpperCase()
                color: root.selectedEvents.length > 0
                  ? root.contentForeground
                  : Qt.darker(root.contentForeground, 1.7)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }
            }
          }

          // ---- Month grid: week numbers down a gutter, then seven day
          //      columns. Dots mark days with events; today is outlined and
          //      the selected day is filled.
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
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle,
                // same as the stock clock.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
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
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
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
                      readonly property bool hot: dayMouse.containsMouse

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      color: isSelected
                        ? Style.selectedStateColor(root.contentForeground, Color.accent)
                        : (hot ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent")
                      border.width: modelData.today && !isSelected ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      Text {
                        textFormat: Text.PlainText
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Style.space(5)
                        text: modelData.day
                        color: parent.isSelected
                          ? root.onSelectedColor
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
                          ? root.onSelectedColor
                          : Style.selectedStateColor(root.contentForeground, Color.accent)
                      }

                      MouseArea {
                        id: dayMouse
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

          // ---- Month stepping spanning the grid, with a sync trigger inboard
          //      of the next chevron. The chevrons sit on the grid's outer
          //      edges, the same edges the rail above uses, so the row reads as
          //      the panel's other full-width rail.
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
                anchors.rightMargin: Style.space(38)
                anchors.verticalCenter: parent.verticalCenter
                iconText: syncProcess.running ? "󰑓" : "󰑐"
                tooltipText: root.syncTooltip()
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                enabled: !syncProcess.running
                onClicked: syncProcess.running = true
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
            }
          }

          // ---- The selected day's agenda.
          Column {
            id: eventSection
            width: gridColumn.width
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)
            visible: root.cacheReady

            Repeater {
              model: root.selectedEvents

              Row {
                id: eventRow
                required property var modelData
                width: eventSection.width
                spacing: Style.space(10)

                Text {
                  id: eventTime
                  textFormat: Text.PlainText
                  // Wide enough for the longest 12-hour range,
                  // "12:00 PM–12:00 PM", without crowding the title.
                  width: Style.space(116)
                  elide: Text.ElideRight
                  text: root.timeRange(modelData)
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Column {
                  width: eventRow.width - eventTime.width - eventRow.spacing
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
            text: "No iCloud events yet — syncing in the background, or press ↻ above."
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
