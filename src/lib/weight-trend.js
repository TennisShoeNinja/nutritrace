/**
 * weight-trend.js: week-over-week weight change for judging the rate of
 * loss (fork addition).
 *
 * Daily weight swings 2-4 lb with water and sodium, so each week is the
 * average of its weigh-ins, and the change is this week's average minus
 * last week's. Weeks run Sunday to Saturday, like the Diary's week strip
 * (weekIsos in weekly-budget.js).
 *
 * The target band is a weekly LOSS as % of body weight: { min: 0.5, max: 1.0 }
 * means losing 0.5-1.0% a week is on target. Faster risks muscle, slower
 * (or a gain) means the deficit isn't there.
 */
import { weekIsos } from './weekly-budget.js';

export const DEFAULT_BAND = { min: 0.5, max: 1.0 };
export const BAND_SETTING_KEY = 'weightRateBand';
const KCAL_PER = { lb: 3500, kg: 7700 };

/** Read a saved band, falling back to the default for anything malformed. */
export function normalizeBand(b) {
  const min = Number(b?.min), max = Number(b?.max);
  if (!Number.isFinite(min) || !Number.isFinite(max) || min < 0 || max <= min) return { ...DEFAULT_BAND };
  return { min, max };
}

/**
 * 'in' = inside the band, 'fast' = losing faster than max,
 * 'slow' = losing slower than min (includes gaining), null = no change known.
 */
export function bandStatus(lossPct, band = DEFAULT_BAND) {
  if (!Number.isFinite(lossPct)) return null;
  const r = (x) => Math.round(x * 100) / 100;   // so 0.5 shown is 0.5 judged
  const v = r(lossPct);
  if (v > band.max) return 'fast';
  if (v < band.min) return 'slow';
  return 'in';
}

const mean = (xs) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;

/**
 * @param {Array<{date: string, weight?: number|null, kcal?: number|null}>} days
 *   Daily rows, weight in `unit`, kcal null when nothing was logged.
 * @param {object} opts
 * @param {string} opts.today  YYYY-MM-DD (local)
 * @param {number} [opts.weeks=5]  weeks to return, the current one last
 * @param {{min:number,max:number}} [opts.band]
 * @param {'lb'|'kg'} [opts.unit='lb']
 * @returns {{ weeks: Array, tdee: number|null }}
 */
export function weeklyTrend(days, { today, weeks = 5, band = DEFAULT_BAND, unit = 'lb' } = {}) {
  const byDate = new Map(days.map(d => [d.date, d]));
  // weeks + 1 so the oldest shown week has a change too
  const starts = [];
  let anchor = weekIsos(today)[0];
  for (let i = 0; i <= weeks; i++) {
    starts.unshift(anchor);
    const d = new Date(anchor + 'T12:00:00'); d.setDate(d.getDate() - 7);
    anchor = isoOf(d);
  }

  const all = starts.map(start => {
    const isos = weekIsos(start);
    const rows = isos.map(iso => byDate.get(iso)).filter(Boolean);
    const ws = rows.map(r => r.weight).filter(v => Number.isFinite(v) && v > 0);
    const ks = rows.map(r => r.kcal).filter(v => Number.isFinite(v) && v > 0);
    return {
      start, end: isos[6],
      partial: today <= isos[6],
      weighIns: ws.length,
      avgWeight: mean(ws),
      kcalDays: ks.length,
      avgKcal: ks.length ? Math.round(mean(ks)) : null,
    };
  });

  const kcalPer = KCAL_PER[unit] || KCAL_PER.lb;
  const out = [];
  for (let i = 1; i < all.length; i++) {
    const w = all[i], prev = all[i - 1];
    let change = null, lossPct = null, tdee = null;
    if (w.avgWeight != null && prev.avgWeight != null) {
      change = w.avgWeight - prev.avgWeight;
      lossPct = -change / prev.avgWeight * 100;
      // Eaten minus stored: a week that lost `change` burned that many more.
      if (w.avgKcal != null) tdee = Math.round(w.avgKcal - change * kcalPer / 7);
    }
    out.push({
      ...w,
      avgWeight: w.avgWeight == null ? null : round(w.avgWeight, 1),
      change: change == null ? null : round(change, 1),
      lossPct: lossPct == null ? null : round(lossPct, 2),
      status: bandStatus(lossPct, band),
      tdee,
    });
  }

  // Overall burn estimate: full weeks only (a half week's average is noisy),
  // weighted equally. Needs at least two.
  const full = out.filter(w => !w.partial && w.tdee != null);
  const tdee = full.length >= 2 ? Math.round(mean(full.map(w => w.tdee))) : null;
  return { weeks: out, tdee };
}

function round(x, n) { const f = 10 ** n; return Math.round(x * f) / f; }
function isoOf(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/**
 * Sample days for a cut at about 259 lb, used until real weigh-ins exist:
 * ~1.8 lb/week down with a ±2 lb daily water swing, 2,100-2,300 kcal.
 * Deterministic so screenshots and tests match.
 */
export function fixtureDays(today, { startWeight = 262, perWeek = 1.8, days = 42 } = {}) {
  const out = [];
  const end = new Date(today + 'T12:00:00');
  let trend = startWeight;
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(end); d.setDate(d.getDate() - i);
    const t = days - 1 - i;
    const swing = Math.sin(t * 2.1) * 1.6 + Math.cos(t * 0.9) * 0.8;
    // A fast start, then on pace, then a stall, so every colour shows
    trend -= (t < 14 ? perWeek * 1.6 : t < 28 ? perWeek : perWeek * 0.3) / 7;
    out.push({
      date: isoOf(d),
      weight: t % 5 === 3 ? null : round(trend + swing, 1),          // skipped a weigh-in
      kcal: t % 7 === 6 ? null : 2150 + Math.round(Math.sin(t) * 180), // unlogged day
    });
  }
  return out;
}
