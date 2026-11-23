/**
 * Weekly calorie budget (fork addition, src/lib/weekly-budget.js):
 * overeating is paid back over the days left, savings are kept.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { weekPlan, weekIsos } from '../src/lib/weekly-budget.js';

const isos = weekIsos('2026-11-25');                    // Sun 22 .. Sat 28
const day = (i, eaten, logged = eaten > 0, target = 2200) => ({ iso: isos[i], target, eaten, logged });
const WED = isos[3];

test('week runs Sunday to Saturday', () => {
  assert.deepEqual([isos[0], isos[6]], ['2026-11-22', '2026-11-28']);
});

test('on target: every day keeps its target', () => {
  const p = weekPlan([day(0, 2200), day(1, 2200), day(2, 2200), day(3, 1000), day(4, 0), day(5, 0), day(6, 0)], WED);
  assert.equal(p.budget, 15400);
  assert.equal(p.todayPlan, 2200);
  assert.equal(p.todayLeft, 1200);
  assert.equal(p.landing, 15400);
});

test('overeating is spread over the days left', () => {
  // 800 over on Monday, 4 days left (Wed..Sat) -> 200 less each
  const p = weekPlan([day(0, 2200), day(1, 3000), day(2, 2200), day(3, 0, false), day(4, 0), day(5, 0), day(6, 0)], WED);
  assert.equal(p.debt, 800);
  assert.equal(p.todayPlan, 2000);
  assert.equal(p.nextPlan, 2000);
  assert.equal(p.landing, 15400);
  assert.equal(p.unpaid, 0);
});

test('a fast is kept as savings, not handed back', () => {
  const p = weekPlan([day(0, 2200), day(1, 0, true), day(2, 2200), day(3, 0, false), day(4, 0), day(5, 0), day(6, 0)], WED);
  assert.equal(p.savings, 2200);
  assert.equal(p.todayPlan, 2200);        // not raised
  assert.equal(p.landing, 15400 - 2200);
});

test('savings cover a later overage first', () => {
  const p = weekPlan([day(0, 1700), day(1, 2700), day(2, 2200), day(3, 0, false), day(4, 0), day(5, 0), day(6, 0)], WED);
  assert.equal(p.debt, 0);
  assert.equal(p.todayPlan, 2200);
});

test('payback stops at 80% of a day and reports what is left over', () => {
  // 3000 over, 4 days left, floor 1760 -> at most 440 x 4 = 1760 paid
  const p = weekPlan([day(0, 2200), day(1, 5200), day(2, 2200), day(3, 0, false), day(4, 0), day(5, 0), day(6, 0)], WED);
  assert.equal(p.todayPlan, 1760);
  assert.equal(p.unpaid, 1240);
  assert.equal(p.landing, 15400 + 1240);
});

test('a day with a different target still pays its share', () => {
  const days = [day(0, 2200), day(1, 4000), day(2, 2200), day(3, 0, false), day(4, 0), day(5, 0), day(6, 0, false, 3000)];
  const p = weekPlan(days, WED);
  const sat = p.days[6];
  assert.equal(p.unpaid, 0);
  assert.ok(sat.plan < 3000 && sat.plan >= 2400);
  assert.equal(p.days.slice(3).reduce((s, d) => s + (d.target - d.plan), 0), 1800);
});

test('unlogged past day counts as on target', () => {
  const p = weekPlan([day(0, 0, false), day(1, 0, false), day(2, 0, false), day(3, 500), day(4, 0), day(5, 0), day(6, 0)], WED);
  assert.equal(p.savings, 0);
  assert.equal(p.landing, 15400);
});

test('a past week has no today', () => {
  const p = weekPlan([day(0, 2000), day(1, 2000), day(2, 2000), day(3, 2000), day(4, 2000), day(5, 2000), day(6, 2000)], '2026-12-30');
  assert.equal(p.todayPlan, null);
  assert.equal(p.eaten, 14000);
  assert.equal(p.landing, 14000);
});
