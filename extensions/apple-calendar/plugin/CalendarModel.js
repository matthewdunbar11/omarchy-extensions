// Pure date math + event helpers for the apple-calendar panel.
// Locale- and Qt-free on purpose (mirrors the stock clock Model.js approach)
// so it runs under node for tests. QML owns display naming via Qt.locale().

var MS_PER_DAY = 86400000

var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

// Stable "yyyy-MM-dd" identity for a day. month is 0-based (JS Date style).
function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null
  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null
  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i
  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fb = coerceWeekStart(fallback)
  return fb === null ? 1 : fb
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

// The name stored back into shell.json when the grid's "W" heading is
// clicked, and the day it flips to (Monday <-> Sunday, the two conventions
// people actually switch between).
function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

// ISO-8601 week number: the week owning the Thursday of that date's
// Monday-based week. Mirrors the clock widget's 'ww' format token.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

// Always six rows of seven days so the popup never changes height. Each row
// carries its ISO week number, the way the stock clock's grid does.
function monthGrid(year, month, weekStart, todayKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var weeks = []
  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var y = cursor.getFullYear(), m = cursor.getMonth(), dd = cursor.getDate()
      var weekday = cursor.getDay()
      if (weekday === 4) thursday = { year: y, month: m, day: dd }
      days.push({
        key: dateKey(y, m, dd),
        year: y, month: m, day: dd, weekday: weekday,
        inMonth: m === month && y === year,
        weekend: weekday === 0 || weekday === 6,
        today: dateKey(y, m, dd) === today
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    // Number every row by the ISO week owning its Thursday, so a row that
    // straddles two weeks still reports the one it mostly belongs to.
    var anchor = thursday || days[0]
    weeks.push({ week: isoWeek(anchor.year, anchor.month, anchor.day), days: days })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

// ---- Event helpers. Cache shape: { days: { "yyyy-MM-dd": [event] } } where
// event = { title, start, end, allDay, calendar } and start/end are "HH:MM"
// local strings ("" when allDay).

function eventsForDay(eventDays, key) {
  var list = (eventDays && eventDays[key]) || []
  return sortEvents(list.slice())
}

function hasEvents(eventDays, key) {
  var list = (eventDays && eventDays[key]) || []
  return list.length > 0
}

function eventCount(eventDays, key) {
  var list = (eventDays && eventDays[key]) || []
  return list.length
}

// All-day first, then by start time, then title — stable for display.
function sortEvents(list) {
  return list.sort(function(a, b) {
    var aa = a.allDay ? 0 : 1, bb = b.allDay ? 0 : 1
    if (aa !== bb) return aa - bb
    var sa = String(a.start || ""), sb = String(b.start || "")
    if (sa !== sb) return sa < sb ? -1 : 1
    var ta = String(a.title || ""), tb = String(b.title || "")
    return ta < tb ? -1 : (ta > tb ? 1 : 0)
  })
}

// "09:00–10:30" or "All day" for the list rows.
function timeRangeText(ev) {
  if (ev.allDay) return "All day"
  var s = String(ev.start || ""), e = String(ev.end || "")
  if (s && e) return s + "–" + e
  return s || e || ""
}

// Split a "yyyy-MM-dd" key back into parts (month 0-based, JS Date style).
function parseKey(key) {
  var parts = String(key || "").split("-")
  if (parts.length !== 3) return null
  var y = parseInt(parts[0], 10), m = parseInt(parts[1], 10) - 1, d = parseInt(parts[2], 10)
  if (!isFinite(y) || !isFinite(m) || !isFinite(d)) return null
  return { year: y, month: m, day: d }
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey,
    parseKey: parseKey,
    keyForDate: keyForDate,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    isoWeek: isoWeek,
    weekdayOrder: weekdayOrder,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    eventsForDay: eventsForDay,
    hasEvents: hasEvents,
    eventCount: eventCount,
    sortEvents: sortEvents,
    timeRangeText: timeRangeText
  }
}
