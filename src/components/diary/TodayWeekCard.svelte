<script>
  /**
   * Diary → Today / This week card (fork addition). Two pages you swipe
   * between: the day's ring (the app's own DaySummaryWidget) and the week's
   * budget (WeekCard). The day's calorie target is the week plan's target,
   * so both pages agree after an over day (src/lib/weekly-budget.js).
   *
   * shortcut: per-day targets come from the saved calorie goal (per-weekday
   * aware); dynamic/adaptive modes use the viewed day's goal for every day.
   * Upgrade if those modes are ever used.
   */
  import { NtApi } from '../../lib/api.js';
  import { localDateStr } from '../../lib/db.js';
  import { Nutrition } from '../../lib/nutrition.js';
  import { resolveGoalFor } from '../../lib/goal-resolver.js';
  import { weekPlan, weekIsos } from '../../lib/weekly-budget.js';
  import DaySummaryWidget from './DaySummaryWidget.svelte';
  import WeekCard from './WeekCard.svelte';

  export let currentDate = localDateStr();
  export let goal = null;            // $goals.calories entry
  export let fallbackGoal = 2000;    // Diary's resolved goal, used when the entry gives none
  export let activityBonus = 0;      // the viewed day's activity kcal the Diary adds to its goal
  export let refreshKey = 0;
  // The day's totals and macro goals, as the Diary already has them
  export let eatenKcal = 0;
  export let protein = 0;
  export let carbs = 0;
  export let fat = 0;
  export let proteinGoal = null;
  export let carbGoal = null;
  export let fatGoal = null;
  export let onOpenSummary = () => {};
  export let onOpenTrends = null;

  let byDate = new Map();   // iso → { kcal, logged }
  let _seq = 0;
  async function load() {
    const mine = ++_seq;
    const all = await NtApi.getAllDiary().catch(() => null);
    if (mine !== _seq || !all) return;
    const wanted = new Set(weekIsos(currentDate));
    const map = new Map();
    for (const entry of all) {
      if (!wanted.has(entry?.date)) continue;
      const items = entry.items || [];
      const kcal = Nutrition.sum(items.map(it => Nutrition.calculate(it))).calories || 0;
      map.set(entry.date, { kcal: Math.round(kcal), logged: items.length > 0 });
    }
    byDate = map;
  }
  $: currentDate, refreshKey, load();

  $: isos = weekIsos(currentDate);
  $: p = weekPlan(isos.map(iso => ({
        iso,
        target: resolveGoalFor(goal, iso) ?? fallbackGoal,
        eaten: byDate.get(iso)?.kcal ?? 0,
        logged: !!byDate.get(iso)?.logged,
      })), localDateStr());
  $: dayGoal = (p.days.find(d => d.iso === currentDate)?.plan ?? fallbackGoal) + (activityBonus || 0);

  // Pager: native scroll-snap; the dots follow the scroll and jump to a page.
  let pagesEl;
  let page = 0;
  function onScroll() {
    if (pagesEl) page = Math.round(pagesEl.scrollLeft / Math.max(pagesEl.clientWidth, 1));
  }
  function show(i) {
    pagesEl?.scrollTo({ left: i * pagesEl.clientWidth, behavior: 'smooth' });
  }
</script>

<section class="twc" aria-label="Today and this week">
  <div class="twc-pages" bind:this={pagesEl} on:scroll={onScroll}>
    <div class="twc-page" aria-hidden={page !== 0}>
      <DaySummaryWidget
        {eatenKcal} {protein} {carbs} {fat}
        goalKcal={dayGoal}
        {proteinGoal} {carbGoal} {fatGoal}
        {onOpenSummary} {onOpenTrends}
      />
    </div>
    <div class="twc-page" aria-hidden={page !== 1}>
      <WeekCard {p} {isos} />
    </div>
  </div>
  <div class="twc-dots">
    <button class="twc-dot" class:on={page === 0} aria-label="Show today" aria-current={page === 0} on:click={() => show(0)}></button>
    <button class="twc-dot" class:on={page === 1} aria-label="Show this week" aria-current={page === 1} on:click={() => show(1)}></button>
  </div>
</section>

<style>
  .twc { margin: 0 var(--page-px) 12px; }
  .twc-pages {
    display: grid;
    grid-auto-flow: column;
    grid-auto-columns: 100%;
    gap: 12px;
    overflow-x: auto;
    scroll-snap-type: x mandatory;
    overscroll-behavior-x: contain;
    scrollbar-width: none;
  }
  .twc-pages::-webkit-scrollbar { display: none; }
  .twc-page { scroll-snap-align: start; min-width: 0; }
  .twc-page > :global(*) { height: 100%; box-sizing: border-box; margin: 0; }
  .twc-dots { display: flex; justify-content: center; gap: 4px; padding-top: 4px; }
  /* 24px hit area around an 8px dot */
  .twc-dot {
    width: 24px; height: 24px; padding: 0; border: none; background: none; cursor: pointer;
    display: flex; align-items: center; justify-content: center;
  }
  .twc-dot::after {
    content: ''; width: 8px; height: 8px; border-radius: 50%;
    background: var(--text-3); opacity: 0.45;
  }
  .twc-dot.on::after { background: var(--accent); opacity: 1; }
</style>
