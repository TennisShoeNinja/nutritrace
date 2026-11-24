/**
 * "This week" coach summary (fork addition, src/lib/week-summary.js):
 * macro averages vs goals, protein days, and the week's weight.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { weekIsos } from '../src/lib/weekly-budget.js';
import { weekNutrition, dayWeight, weekWeight, shiftWeek, fixtureWithings, goalDir } from '../src/lib/week-summary.js';

const isos = weekIsos('2026-11-25');               // Sun 22 .. Sat 28
const prevIsos = shiftWeek(isos);
const WED = isos[3];
const GOALS = { kcal: 2200, protein: 234, carbs: 179, fat: 61 };
const day = (i, kcal, protein, carbs, fat, logged = true) => ({ iso: isos[i], logged, kcal, protein, carbs, fat });
const row = (s, k) => s.rows.find(r => r.key === k);

test('last week is the 7 days before', () => {
  assert.deepEqual([prevIsos[0], prevIsos[6]], ['2026-11-15', '2026-11-21']);
});

test('averages finished logged days only and checks each goal its own way', () => {
  const s = weekNutrition([
    day(0, 2100, 240, 170, 60),
    day(1, 2300, 230, 190, 55),
    day(2, 0, 0, 0, 0, false),        // nothing logged: left out
    day(3, 900, 80, 60, 20),          // today, still eating: left out
    day(4, 0, 0, 0, 0, false), day(5, 0, 0, 0, 0, false), day(6, 0, 0, 0, 0, false),
  ], GOALS, WED);
  assert.equal(s.n, 2);
  assert.deepEqual(row(s, 'kcal'),    { ...row(s, 'kcal'), value: 2200, goal: 2200, ok: true });   // at max is fine
  assert.deepEqual(row(s, 'protein'), { ...row(s, 'protein'), value: 235, ok: true });            // min, over
  assert.equal(row(s, 'carbs').value, 180);
  assert.equal(row(s, 'carbs').ok, false);                                                        // max, over
  assert.equal(row(s, 'fat').ok, true);
  assert.equal(s.proteinHit, 1);
  assert.deepEqual(s.proteinDays.map(d => d.hit), [true, false]);
});

test('per-day kcal targets average into the kcal goal', () => {
  const days = [day(0, 2000, 0, 0, 0), day(1, 2000, 0, 0, 0)].map((d, i) => ({ ...d, kcalGoal: i ? 2400 : 2000 }));
  const s = weekNutrition(days, GOALS, WED);
  assert.equal(row(s, 'kcal').goal, 2200);
});

test('no logged days: no averages, nothing marked', () => {
  const s = weekNutrition([day(0, 0, 0, 0, 0, false)], GOALS, WED);
  assert.equal(s.n, 0);
  assert.ok(s.rows.every(r => r.value == null && r.ok == null));
  assert.equal(s.proteinHit, 0);
});

test('weight: device first, then the diary, in the chosen unit', () => {
  const src = {
    withings: { [isos[0]]: { weight_kg: { value: 100 } } },
    fitbit:   { [isos[1]]: { weight_kg: 90 } },
    entries:  { [isos[2]]: { body_stats: { weight: 200, weight_unit: 'lb' } } },
  };
  assert.equal(Math.round(dayWeight(isos[0], src, 'lb') * 10) / 10, 220.5);
  assert.equal(dayWeight(isos[0], src, 'kg'), 100);
  assert.equal(dayWeight(isos[1], src, 'kg'), 90);
  assert.equal(dayWeight(isos[2], src, 'lb'), 200);
  assert.equal(dayWeight(isos[2], src, 'kg'), 90.7);
  assert.equal(dayWeight(isos[3], src, 'kg'), null);
});

test('weight: Withings wins over the diary on the same day', () => {
  const src = { withings: { [isos[0]]: { weight_kg: { value: 95 } } }, entries: { [isos[0]]: { body_stats: { weight: 99, weight_unit: 'kg' } } } };
  assert.equal(dayWeight(isos[0], src, 'kg'), 95);
});

test('week average and change vs last week skip missing days', () => {
  const src = { withings: fixtureWithings(prevIsos, isos, isos[6]) };
  const w = weekWeight(isos, prevIsos, iso => dayWeight(iso, src, 'kg'));
  assert.equal(w.count, 6);
  assert.equal(w.days[2].value, null);
  assert.equal(w.avg, 95.1);              // (95.6+95.2+95.1+94.9+95.0+94.7)/6
  assert.equal(w.prevAvg, 96);            // 672.2/7 = 96.03
  assert.equal(w.change, -0.9);
});

test('change is computed from unrounded averages, in lb too', () => {
  const src = { withings: fixtureWithings(prevIsos, isos, isos[6]) };
  const w = weekWeight(isos, prevIsos, iso => dayWeight(iso, src, 'lb'));
  assert.equal(w.change, -2.1);
});

test('no weigh-ins last week: no change shown', () => {
  const src = { withings: { [isos[0]]: { weight_kg: { value: 95 } } } };
  const w = weekWeight(isos, prevIsos, iso => dayWeight(iso, src, 'kg'));
  assert.equal(w.avg, 95);
  assert.equal(w.prevAvg, null);
  assert.equal(w.change, null);
});

test('fixture leaves future days empty', () => {
  const f = fixtureWithings(prevIsos, isos, WED);
  assert.ok(f[isos[3]] && !f[isos[4]]);
});

test('a saved goal decides min or max', () => {
  assert.equal(goalDir({ min: 234 }), 'min');
  assert.equal(goalDir({ max: 179 }), 'max');
  assert.equal(goalDir({ min: 150, max: 179 }), 'max');
  assert.equal(goalDir(null), null);
  const s = weekNutrition([day(0, 2100, 200, 170, 60)], GOALS, WED, { carbs: 'min' });
  assert.equal(row(s, 'carbs').min, true);
  assert.equal(row(s, 'carbs').ok, false);     // 170 under a 179 floor
  assert.equal(row(s, 'protein').min, true);   // default kept
});
