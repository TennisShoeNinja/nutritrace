<script>
  /**
   * Diary → Today / This week card (fork addition). Two pages you swipe
   * between: the day's ring (the app's own DaySummaryWidget) and the week's
   * budget plus the coach summary: macro averages and weight (WeekCard,
   * src/lib/week-summary.js). The day's calorie target is the week plan's
   * target, so both pages agree after an over day (src/lib/weekly-budget.js).
   *
   * shortcut: per-day targets come from the saved calorie goal (per-weekday
   * aware); dynamic/adaptive modes use the viewed day's goal for every day.
   * Upgrade if those modes are ever used.
   */
  import { onMount } from 'svelte';
  import { NtApi } from '../../lib/api.js';
  import { localDateStr } from '../../lib/db.js';
  import { Nutrition } from '../../lib/nutrition.js';
  import { resolveGoalFor } from '../../lib/goal-resolver.js';
  import { weekPlan, weekIsos } from '../../lib/weekly-budget.js';
  import { weekNutrition, weekWeight, dayWeight, shiftWeek, fixtureWithings, goalDir } from '../../lib/week-summary.js';
  import { goals, weightUnit, withingsEnabled, fitbitFamilyEnabled, healthConnectEnabled } from '../../stores/settings.js';
  import { isAndroid } from '../../lib/platform.js';
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

  let byDate = new Map();   // iso → { kcal, protein, carbs, fat, logged }
  let weightSrc = {};       // { withings, fitbit, hc, entries }: this week and last, as Statistics reads weight
  let weightSample = false; // dev only: no weigh-ins yet, showing fixtures
  let _seq = 0;
  async function load() {
    const mine = ++_seq;
    const all = await NtApi.getAllDiary().catch(() => null);
    if (mine !== _seq || !all) return;
    const thisWeek = weekIsos(currentDate);
    const lastWeek = shiftWeek(thisWeek);
    const wanted = new Set(thisWeek);
    const both = new Set([...lastWeek, ...thisWeek]);
    const map = new Map();
    const entries = {};
    for (const entry of all) {
      if (both.has(entry?.date)) entries[entry.date] = entry;
      if (!wanted.has(entry?.date)) continue;
      const items = entry.items || [];
      const t = Nutrition.sum(items.map(it => Nutrition.calculate(it)));
      map.set(entry.date, {
        kcal: Math.round(t.calories || 0), protein: t.proteins || 0,
        carbs: t.carbohydrates || 0, fat: t.fat || 0, logged: items.length > 0,
      });
    }
    byDate = map;
    weightSrc = { entries };
    loadWeights(mine, lastWeek[0], thisWeek[6], entries, lastWeek, thisWeek);
  }
  async function loadWeights(mine, from, to, entries, lastWeek, thisWeek) {
    const q = `from=${from}&to=${to}`;
    const [withings, fitbit, hc] = await Promise.all([
      $withingsEnabled ? NtApi.get(`/api/wellness/withings/data?${q}`).catch(() => ({})) : {},
      $fitbitFamilyEnabled ? NtApi.get(`/api/wellness/fitbit/data?${q}`).catch(() => ({})) : {},
      $healthConnectEnabled && isAndroid
        ? import('../../lib/db-native.js').then(m => m.dbGetWellnessGrouped(from, to, 'health_connect')).catch(() => ({}))
        : {},
    ]);
    if (mine !== _seq) return;
    const src = { withings, fitbit, hc, entries };
    const any = [...lastWeek, ...thisWeek].some(iso => dayWeight(iso, src, 'kg') != null);
    weightSample = !any && import.meta.env.DEV;
    weightSrc = weightSample ? { ...src, withings: fixtureWithings(lastWeek, thisWeek, localDateStr()) } : src;
  }
  $: currentDate, refreshKey, load();

  $: isos = weekIsos(currentDate);
  $: p = weekPlan(isos.map(iso => ({
        iso,
        target: resolveGoalFor(goal, iso) ?? fallbackGoal,
        eaten: byDate.get(iso)?.kcal ?? 0,
        logged: !!byDate.get(iso)?.logged,
      })), localDateStr());
  $: summary = weekNutrition(p.days.map(d => ({
        iso: d.iso, kcalGoal: d.target, logged: d.logged,
        ...(byDate.get(d.iso) || { kcal: 0, protein: 0, carbs: 0, fat: 0 }),
      })), { protein: proteinGoal, carbs: carbGoal, fat: fatGoal }, localDateStr(), {
        kcal: goalDir(goal), protein: goalDir($goals?.proteins),
        carbs: goalDir($goals?.carbohydrates), fat: goalDir($goals?.fat),
      });
  $: weight = weekWeight(isos, shiftWeek(isos), iso => dayWeight(iso, weightSrc, $weightUnit));
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
  // The pager takes the shown page's height, so the short Today page
  // doesn't leave the week page's height as empty space under it.
  let pageEls = [];
  let height = null;
  function measure() { height = pageEls[page]?.offsetHeight || null; }
  $: page, measure();
  onMount(() => {
    const ro = new ResizeObserver(measure);
    pageEls.forEach(el => el && ro.observe(el));
    return () => ro.disconnect();
  });
</script>

<section class="twc" aria-label="Today and this week">
  <div class="twc-pages" bind:this={pagesEl} on:scroll={onScroll} style:height={height ? height + 'px' : null}>
    <div class="twc-page" bind:this={pageEls[0]} aria-hidden={page !== 0}>
      <DaySummaryWidget
        {eatenKcal} {protein} {carbs} {fat}
        goalKcal={dayGoal}
        {proteinGoal} {carbGoal} {fatGoal}
        {onOpenSummary} {onOpenTrends}
      />
    </div>
    <div class="twc-page" bind:this={pageEls[1]} aria-hidden={page !== 1}>
      <WeekCard {p} {isos} {summary} {weight} unit={$weightUnit} sample={weightSample} />
    </div>
  </div>
  <div class="twc-dots">
    <button class="twc-dot" class:on={page === 0} aria-label="Show today" aria-current={page === 0} on:click={() => show(0)}></button>
    <button class="twc-dot" class:on={page === 1} aria-label="Show this week" aria-current={page === 1} on:click={() => show(1)}></button>
  </div>
</section>

<style>
  /* No margin of its own: the Diary already pads and spaces its cards. */
  .twc { min-width: 0; }
  .twc-pages {
    display: grid;
    grid-auto-flow: column;
    grid-auto-columns: 100%;
    gap: 12px;
    overflow-x: auto;
    scroll-snap-type: x mandatory;
    overscroll-behavior-x: contain;
    scrollbar-width: none;
    align-items: start;
    overflow-y: hidden;
    transition: height 0.2s ease;
  }
  .twc-pages::-webkit-scrollbar { display: none; }
  .twc-page { scroll-snap-align: start; min-width: 0; }
  .twc-page > :global(*) { box-sizing: border-box; margin: 0; }
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
