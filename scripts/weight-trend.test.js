/**
 * Week-over-week weight change (fork addition, src/lib/weight-trend.js):
 * weekly averages, % of body weight, the target band, and the burn estimate.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { weeklyTrend, bandStatus, normalizeBand, fixtureDays, DEFAULT_BAND } from '../src/lib/weight-trend.js';
import { weekIsos } from '../src/lib/weekly-budget.js';

const TODAY = '2026-11-25';                      // a Wednesday; week is Sun 22 .. Sat 28

// One weigh-in per day at `w(weekIndex, dayIndex)`, oldest week first.
function daysFor(weeks, w, kcal = 2200) {
  const out = [];
  const starts = [];
  let a = weekIsos(TODAY)[0];
  for (let i = 0; i < weeks; i++) {
    starts.unshift(a);
    const d = new Date(a + 'T12:00:00'); d.setDate(d.getDate() - 7);
    a = d.toISOString().slice(0, 10);
  }
  starts.forEach((s, wi) => weekIsos(s).forEach((iso, di) => {
    if (iso <= TODAY) out.push({ date: iso, weight: w(wi, di), kcal });
  }));
  return out;
}

test('returns the requested weeks, current week last and marked partial', () => {
  const r = weeklyTrend(daysFor(6, () => 259), { today: TODAY, weeks: 5 });
  assert.equal(r.weeks.length, 5);
  assert.equal(r.weeks.at(-1).start, '2026-11-22');
  assert.equal(r.weeks.at(-1).partial, true);
  assert.equal(r.weeks[0].partial, false);
});

test('averages weigh-ins so one salty day does not swing the week', () => {
  // flat 259 with one +4 lb spike day in week 4
  const r = weeklyTrend(daysFor(6, (wi, di) => (wi === 4 && di === 2 ? 263 : 259)), { today: TODAY });
  const w = r.weeks[3];                              // week index 4 of 6
  assert.equal(w.avgWeight, 259.6);
  assert.equal(w.change, 0.6);
});

test('change in lb and as % of last week, judged against the band', () => {
  // lose 2 lb a week from 260: 2/260 = 0.77%, inside 0.5-1.0
  const r = weeklyTrend(daysFor(6, wi => 260 - 2 * wi), { today: TODAY });
  const w = r.weeks[1];
  assert.equal(w.change, -2);
  assert.equal(w.lossPct, 0.78);
  assert.equal(w.status, 'in');
});

test('too fast, too slow, and a gain', () => {
  assert.equal(bandStatus(1.4, DEFAULT_BAND), 'fast');
  assert.equal(bandStatus(0.2, DEFAULT_BAND), 'slow');
  assert.equal(bandStatus(-0.3, DEFAULT_BAND), 'slow');
  assert.equal(bandStatus(0.5, DEFAULT_BAND), 'in');
  assert.equal(bandStatus(1.0, DEFAULT_BAND), 'in');
  assert.equal(bandStatus(NaN, DEFAULT_BAND), null);
});

test('a custom band from the coach changes the verdict', () => {
  const r = weeklyTrend(daysFor(6, wi => 260 - 2 * wi), { today: TODAY, band: { min: 0.3, max: 0.6 } });
  assert.equal(r.weeks[1].status, 'fast');
});

test('a week with no weigh-ins has no change, and neither does the next', () => {
  const r = weeklyTrend(daysFor(6, (wi) => (wi === 3 ? null : 259)), { today: TODAY });
  assert.equal(r.weeks[2].avgWeight, null);
  assert.equal(r.weeks[2].change, null);
  assert.equal(r.weeks[3].change, null);
  assert.equal(r.weeks[3].status, null);
});

test('burn estimate: eating 2200 and losing 2 lb a week is about 3200 a day', () => {
  const r = weeklyTrend(daysFor(6, wi => 260 - 2 * wi, 2200), { today: TODAY });
  assert.equal(r.weeks[1].tdee, 3200);
  assert.equal(r.tdee, 3200);                        // full weeks only
});

test('burn estimate in kg uses 7700 kcal/kg', () => {
  const r = weeklyTrend(daysFor(6, wi => 118 - 0.7 * wi, 2200), { today: TODAY, unit: 'kg' });
  assert.equal(r.weeks[1].tdee, 2200 + 770);
});

test('a bad saved band falls back to the default', () => {
  assert.deepEqual(normalizeBand(null), DEFAULT_BAND);
  assert.deepEqual(normalizeBand({ min: 1, max: 0.5 }), DEFAULT_BAND);
  assert.deepEqual(normalizeBand({ min: '0.4', max: '0.8' }), { min: 0.4, max: 0.8 });
});

test('fixture covers fast, in-band and slow weeks', () => {
  const r = weeklyTrend(fixtureDays(TODAY), { today: TODAY });
  const s = new Set(r.weeks.map(w => w.status));
  assert.ok(s.has('fast') && s.has('in') && s.has('slow'), [...s].join(','));
});
