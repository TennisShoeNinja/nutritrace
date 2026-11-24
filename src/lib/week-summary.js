/**
 * week-summary.js: the "This week" card's coach summary (fork addition).
 * Pure functions, no app imports beyond the body-stat unit reader, so
 * scripts/week-summary.test.js can run them under node.
 *
 * - weekNutrition: average kcal / protein / carbs / fat over the week's
 *   finished, logged days, each against its goal, and the days protein
 *   was hit. Today is left out while it's still being eaten.
 * - dayWeight: one day's weight in the display unit, read the way
 *   Statistics' weight trend does (Withings, then Fitbit/Google Health/
 *   Health Connect, then local Health Connect, then the diary's body stats).
 * - weekWeight: each day's weight, the week's average and the change vs
 *   the week before's average.
 */
import { readBodyStat } from './body-stats-unit.js';

const LB_PER_KG = 2.20462;

/** Goal direction: protein is a floor, the rest are ceilings. */
export const MACROS = [
  { key: 'kcal',    label: 'Calories', unit: 'kcal', min: false },
  { key: 'protein', label: 'Protein',  unit: 'g',    min: true  },
  { key: 'carbs',   label: 'Carbs',    unit: 'g',    min: false },
  { key: 'fat',     label: 'Fat',      unit: 'g',    min: false },
];

/**
 * @param {Array<{iso, logged, kcal, protein, carbs, fat, kcalGoal?}>} days the week, in order
 * @param {{kcal?, protein?, carbs?, fat?}} goals goal per macro (kcal can also come per day)
 * @param {string} today YYYY-MM-DD
 * @param {{kcal?, protein?, carbs?, fat?}} [dirs] 'min' | 'max' per macro when the
 *   saved goal says which (see goalDir); otherwise MACROS' default.
 */
export function weekNutrition(days, goals, today, dirs = {}) {
  const counted = days.filter(d => d.logged && d.iso < today);
  const n = counted.length;
  const avg = k => n ? counted.reduce((s, d) => s + (d[k] || 0), 0) / n : null;
  const kcalGoal = n && counted.every(d => d.kcalGoal != null)
    ? counted.reduce((s, d) => s + d.kcalGoal, 0) / n
    : (goals.kcal ?? null);

  const rows = MACROS.map(base => {
    const m = dirs[base.key] ? { ...base, min: dirs[base.key] === 'min' } : base;
    const value = avg(m.key);
    const goal = m.key === 'kcal' ? kcalGoal : (goals[m.key] ?? null);
    const ok = value == null || goal == null ? null
      : m.min ? value >= goal : value <= goal;
    return { ...m, value: value == null ? null : Math.round(value), goal: goal == null ? null : Math.round(goal), ok };
  });

  const pGoal = goals.protein ?? null;
  const proteinDays = counted.map(d => ({ iso: d.iso, hit: pGoal != null && (d.protein || 0) >= pGoal }));
  return {
    n,
    rows,
    proteinHit: proteinDays.filter(d => d.hit).length,
    proteinDays,
  };
}

/** 'min' when a saved goal entry ({min, max}) only sets a floor, 'max' when it sets a ceiling, else null. */
export function goalDir(g) {
  if (!g) return null;
  if (g.max != null) return 'max';
  if (g.min != null) return 'min';
  return null;
}

/**
 * One day's weight in `unit` ('lb' | 'kg'), or null.
 * @param {string} iso
 * @param {{withings?, fitbit?, hc?, entries?}} src  date-keyed maps as the
 *   wellness endpoints return them; entries maps date → diary entry.
 */
export function dayWeight(iso, src, unit) {
  const kg = src.withings?.[iso]?.weight_kg?.value
    ?? src.fitbit?.[iso]?.weight_kg
    ?? src.hc?.[iso]?.weight_kg
    ?? null;
  if (kg != null && Number.isFinite(Number(kg))) {
    const v = Number(kg);
    return unit === 'lb' ? v * LB_PER_KG : v;
  }
  const entry = src.entries?.[iso];
  const bs = entry?.body_stats || entry?.bodyStats;
  return bs ? readBodyStat(bs, 'weight', unit, null) : null;
}

const mean = xs => xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : null;
const r1 = x => x == null ? null : Math.round(x * 10) / 10;

/**
 * @param {string[]} isos this week's 7 dates
 * @param {string[]} prevIsos last week's 7 dates
 * @param {(iso: string) => number|null} weightOf
 */
export function weekWeight(isos, prevIsos, weightOf) {
  const days = isos.map(iso => ({ iso, value: r1(weightOf(iso)) }));
  const here = days.map(d => d.value).filter(v => v != null);
  const prev = prevIsos.map(weightOf).filter(v => v != null);
  const avg = mean(here);
  const prevAvg = mean(prev);
  return {
    days,
    count: here.length,
    avg: r1(avg),
    prevAvg: r1(prevAvg),
    change: avg != null && prevAvg != null ? r1(avg - prevAvg) : null,
  };
}

/** Previous week's dates, one week before each of `isos`. */
export function shiftWeek(isos, weeks = -1) {
  return isos.map(iso => {
    const d = new Date(iso + 'T12:00:00');
    d.setDate(d.getDate() + 7 * weeks);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  });
}

/**
 * Sample weigh-ins (kg) for dev until real Withings data is in the store:
 * last week around 96 kg, this week trending down, one missed day.
 * Returned in the same shape as the Withings endpoint.
 */
export function fixtureWithings(prevIsos, isos, today) {
  const prev = [96.4, 96.1, 96.3, 95.9, 96.0, 95.8, 95.7];
  const cur  = [95.6, 95.2, null, 95.1, 94.9, 95.0, 94.7];
  const out = {};
  prevIsos.forEach((iso, i) => { out[iso] = { weight_kg: { value: prev[i] } }; });
  isos.forEach((iso, i) => { if (cur[i] != null && iso <= today) out[iso] = { weight_kg: { value: cur[i] } }; });
  return out;
}
