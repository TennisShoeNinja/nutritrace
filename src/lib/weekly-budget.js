/**
 * weekly-budget.js: the week's calories as one budget (fork addition).
 *
 * The week's budget is the sum of each day's own calorie target. Eating
 * over target is paid back: the overage is spread evenly over the days
 * left, never pushing a day below PAYBACK_FLOOR of its own target. Eating
 * under target (a fast, a light day) is kept as savings and is NOT handed
 * back to the other days, so a fast lowers the week instead of being eaten
 * later. A past day with nothing logged counts as on target (unknown, so
 * neither debt nor savings).
 */

export const PAYBACK_FLOOR = 0.8;

/**
 * @param {Array<{iso: string, target: number, eaten: number, logged: boolean}>} days
 *   The week's days in order.
 * @param {string} today YYYY-MM-DD (local).
 */
export function weekPlan(days, today) {
  const past = days.filter(d => d.iso < today);
  const rest = days.filter(d => d.iso >= today);

  // Positive = eaten over target so far; negative = saved.
  const balance = past.reduce((s, d) => s + (d.logged ? d.eaten - d.target : 0), 0);
  const debt = Math.max(0, balance);
  const savings = Math.max(0, -balance);

  // Spread the debt evenly; a day that hits its floor passes its share on.
  const plan = new Map(rest.map(d => [d.iso, d.target]));
  let owed = debt;
  let open = rest.slice();
  while (owed > 0.5 && open.length) {
    const share = owed / open.length;
    const next = [];
    for (const d of open) {
      const floor = Math.round(d.target * PAYBACK_FLOOR);
      const cut = Math.min(share, plan.get(d.iso) - floor);
      plan.set(d.iso, plan.get(d.iso) - cut);
      owed -= cut;
      if (plan.get(d.iso) > floor) next.push(d);
    }
    open = next;  // either all of it was paid, or a day reached its floor and drops out
  }

  const out = days.map(d => {
    const state = d.iso < today ? 'past' : d.iso === today ? 'today' : 'future';
    const p = plan.has(d.iso) ? Math.round(plan.get(d.iso)) : d.target;
    return { ...d, state, plan: p };
  });

  const budget = days.reduce((s, d) => s + d.target, 0);
  const eaten = days.reduce((s, d) => s + (d.iso <= today ? d.eaten : 0), 0);
  // Where the week ends if every day left is eaten to plan (today at least
  // what's already eaten); unlogged past days count at target.
  const landing = out.reduce((s, d) => s +
    (d.state === 'past' ? (d.logged ? d.eaten : d.target)
      : d.state === 'today' ? Math.max(d.eaten, d.plan)
      : d.plan), 0);
  const todayDay = out.find(d => d.state === 'today') || null;

  return {
    days: out,
    budget,
    eaten,
    left: budget - eaten,
    debt: Math.round(debt),
    savings: Math.round(savings),
    unpaid: Math.round(Math.max(0, owed)),
    landing: Math.round(landing),
    todayPlan: todayDay ? todayDay.plan : null,
    todayLeft: todayDay ? todayDay.plan - todayDay.eaten : null,
    nextPlan: out.find(d => d.state === 'future')?.plan ?? null,
  };
}

/** The 7 YYYY-MM-DD dates of the Sunday-to-Saturday week holding `iso` (same week as the Diary's week strip). */
export function weekIsos(iso) {
  const anchor = new Date(iso + 'T12:00:00');
  const out = [];
  for (let i = 0; i < 7; i++) {
    const d = new Date(anchor);
    d.setDate(anchor.getDate() - anchor.getDay() + i);
    out.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`);
  }
  return out;
}
