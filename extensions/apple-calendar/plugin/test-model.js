// Node tests for CalendarModel.js (Qt-free by design: `node test-model.js`).
var assert = require("assert");
var M = require("./CalendarModel.js");

// dateKey: month is 0-based.
assert.strictEqual(M.dateKey(2026, 0, 5), "2026-01-05");
assert.strictEqual(M.dateKey(2026, 8, 19), "2026-09-19");
assert.deepStrictEqual(M.parseKey("2026-09-19"), { year: 2026, month: 8, day: 19 });
assert.strictEqual(M.parseKey("nope"), null);

// monthGrid: always 6x7, keys unique + sequential.
var weeks = M.monthGrid(2026, 8, 1, "2026-09-19");
assert.strictEqual(weeks.length, 6);
var keys = [];
weeks.forEach(function(w) {
  assert.strictEqual(w.days.length, 7);
  w.days.forEach(function(d) { keys.push(d.key); });
});
assert.strictEqual(new Set(keys).size, 42);
assert.ok(keys.indexOf("2026-09-19") !== -1);
// First cell: Monday-start Sept 2026 -> Monday Aug 31.
assert.strictEqual(keys[0], "2026-08-31");
assert.strictEqual(weeks[0].days[0].inMonth, false);
// Today flag only on today.
var todayCells = keys.filter(function(k, i) {
  var flat = []; weeks.forEach(function(w) { flat = flat.concat(w.days); });
  return flat[i].today;
});
assert.deepStrictEqual(todayCells, ["2026-09-19"]);
// Sunday start shifts grid: first cell Sunday Aug 30.
assert.strictEqual(M.monthGrid(2026, 8, 0, "")[0].days[0].key, "2026-08-30");
// Feb leap year still 6 rows.
assert.strictEqual(M.monthGrid(2024, 1, 1, "").length, 6);

// ISO week numbers on each row (Thursday-owned), matching the stock clock.
assert.strictEqual(M.isoWeek(2026, 0, 1), 1);
assert.strictEqual(M.isoWeek(2025, 11, 29), 1);
assert.strictEqual(M.isoWeek(2026, 8, 19), 38);
assert.strictEqual(M.isoWeek(2026, 11, 31), 53);
var allWeeks = M.monthGrid(2026, 8, 1, "2026-09-19");
assert.strictEqual(allWeeks[0].week, 36);          // row starting Mon Aug 31
assert.strictEqual(allWeeks[2].week, 38);          // row holding Sat Sep 19
var weekByDay = {};
allWeeks.forEach(function(w) { w.days.forEach(function(d) { weekByDay[d.key] = w.week; }); });
assert.strictEqual(weekByDay["2026-09-19"], 38);

// Week-start toggle: Monday <-> Sunday, and the setting name written back.
assert.strictEqual(M.toggledWeekStart(1), 0);
assert.strictEqual(M.toggledWeekStart(0), 1);
assert.strictEqual(M.weekStartSettingName(1), "monday");
assert.strictEqual(M.weekStartSettingName(0), "sunday");

// stepMonth across year boundary.
assert.deepStrictEqual(M.stepMonth(2026, 11, 1), { year: 2027, month: 0 });
assert.deepStrictEqual(M.stepMonth(2026, 0, -1), { year: 2025, month: 11 });

// weekdayOrder.
assert.deepStrictEqual(M.weekdayOrder(1), [1, 2, 3, 4, 5, 6, 0]);
assert.deepStrictEqual(M.weekdayOrder(0), [0, 1, 2, 3, 4, 5, 6]);

// Events: sort all-day first, then time, then title.
var evs = [
  { title: "b", start: "10:00", end: "11:00", allDay: false },
  { title: "a", start: "09:00", end: "09:30", allDay: false },
  { title: "holiday", start: "", end: "", allDay: true }
];
var sorted = M.sortEvents(evs);
assert.strictEqual(sorted[0].title, "holiday");
assert.strictEqual(sorted[1].title, "a");
assert.strictEqual(M.timeRangeText(sorted[1]), "9:00 AM–9:30 AM");
assert.strictEqual(M.timeRangeText(sorted[0]), "All day");

// formatTime12: 24-hour cache strings -> US 12-hour, edge cases included.
assert.strictEqual(M.formatTime12("00:00"), "12:00 AM");
assert.strictEqual(M.formatTime12("00:30"), "12:30 AM");
assert.strictEqual(M.formatTime12("09:05"), "9:05 AM");
assert.strictEqual(M.formatTime12("12:00"), "12:00 PM");
assert.strictEqual(M.formatTime12("12:45"), "12:45 PM");
assert.strictEqual(M.formatTime12("13:00"), "1:00 PM");
assert.strictEqual(M.formatTime12("17:30"), "5:30 PM");
assert.strictEqual(M.formatTime12("23:59"), "11:59 PM");
assert.strictEqual(M.formatTime12(""), "");
assert.strictEqual(M.formatTime12("noon"), "noon");
assert.strictEqual(M.timeRangeText({ start: "17:30", end: "19:30", allDay: false }), "5:30 PM–7:30 PM");
assert.strictEqual(M.timeRangeText({ start: "11:30", end: "13:00", allDay: false }), "11:30 AM–1:00 PM");
assert.strictEqual(M.timeRangeText({ start: "09:00", end: "", allDay: false }), "9:00 AM");

var days = { "2026-09-19": evs };
assert.strictEqual(M.hasEvents(days, "2026-09-19"), true);
assert.strictEqual(M.hasEvents(days, "2026-09-20"), false);
assert.strictEqual(M.eventCount(days, "2026-09-19"), 3);
assert.strictEqual(M.eventsForDay(days, "2026-09-20").length, 0);

console.log("CalendarModel.js: all tests pass");
