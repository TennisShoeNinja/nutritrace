<script>
  /**
   * "This week" page of the Diary's Today/Week card (fork addition): what's
   * left of the week, today's plan, and a bar per day. Data and math come
   * from TodayWeekCard.svelte and src/lib/weekly-budget.js.
   */
  export let p;          // weekPlan() result
  export let isos = [];  // the week's 7 dates

  const DOW = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  const fmt = n => Math.round(n).toLocaleString();
  const fmtShort = n => n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(Math.round(n));
  const dateLabel = iso => new Date(iso + 'T12:00:00').toLocaleDateString(undefined, { month: 'short', day: 'numeric' });

  $: maxBar = Math.max(...p.days.map(d => Math.max(d.eaten, d.plan, d.target)), 1);
  $: bars = p.days.map(d => {
        const shown = d.state === 'past' ? (d.logged ? d.eaten : d.target) : d.plan;
        return {
          ...d,
          dow: DOW[new Date(d.iso + 'T12:00:00').getDay()],
          heightPct: Math.round(Math.max(shown, d.eaten) / maxBar * 100),
          fillPct: d.state === 'past' ? 100 : Math.min(100, Math.round(d.eaten / Math.max(d.plan, 1) * 100)),
          over: d.eaten > (d.state === 'past' ? d.target : d.plan),
          label: d.state === 'past' ? (d.logged ? fmtShort(d.eaten) : '—') : fmtShort(d.plan),
          aria: d.state === 'past'
            ? (d.logged ? `${d.iso}: ${d.eaten} of ${d.target} kcal` : `${d.iso}: nothing logged`)
            : `${d.iso}: ${d.eaten} eaten, plan ${d.plan} kcal`,
        };
      });
  $: usedPct = Math.min(100, Math.round(p.eaten / Math.max(p.budget, 1) * 100));
  $: inWeek = p.todayPlan != null;
</script>

<section class="week-card" aria-label="This week">
  <header class="wc-head">
    <span class="wc-title">This week</span>
    <span class="wc-range">{dateLabel(isos[0])} – {dateLabel(isos[6])}</span>
  </header>

  <div class="wc-big">
    <span class="wc-left">{fmt(p.left)}</span>
    <span class="wc-sub">kcal left of {fmt(p.budget)} · {fmt(p.eaten)} eaten</span>
  </div>

  <div class="wc-track" role="img" aria-label="{usedPct}% of the week's budget eaten">
    <span class="wc-fill" style="width:{usedPct}%"></span>
  </div>

  {#if inWeek}
    <p class="wc-note" class:warn={p.unpaid > 0}>
      {#if p.debt > 0}
        <strong>{fmt(p.debt)} over so far.</strong> {fmt(p.todayPlan)} today{#if p.nextPlan != null}, then about {fmt(p.nextPlan)} a day{/if}.
        {#if p.unpaid > 0}<br>Can't fit all of it back: the week lands {fmt(p.unpaid)} over.{/if}
      {:else if p.savings > 0}
        <strong>{fmt(p.savings)} under so far,</strong> kept as savings. {fmt(p.todayPlan)} today, as usual.
      {:else}
        <strong>On plan.</strong> {fmt(p.todayPlan)} today, {fmt(Math.max(0, p.todayLeft))} left.
      {/if}
    </p>
  {/if}

  <div class="wc-bars">
    {#each bars as b (b.iso)}
      <div class="wc-col" class:today={b.state === 'today'}>
        <span class="wc-num">{b.label}</span>
        <div class="wc-bar-area">
          <div
            class="wc-bar wc-{b.state}"
            class:unlogged={b.state === 'past' && !b.logged}
            style="height:{b.heightPct}%"
            role="img"
            aria-label={b.aria}
          >
            {#if b.state !== 'past' || b.logged}
              <span class="wc-bar-fill" class:over={b.over} style="height:{b.fillPct}%"></span>
            {/if}
          </div>
        </div>
        <span class="wc-dow">{b.dow}</span>
      </div>
    {/each}
  </div>

  <p class="wc-foot">On plan the week lands at <strong>{fmt(p.landing)}</strong></p>
</section>

<style>
  .week-card {
    background: var(--surface-1);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    padding: 12px 14px;
    height: 100%;
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .wc-head { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
  .wc-title { font-size: 14px; font-weight: 600; color: var(--text-1); }
  .wc-range { font-size: 12px; color: var(--text-3); }
  .wc-big { display: flex; flex-direction: column; gap: 2px; }
  .wc-left { font-size: 28px; font-weight: 700; line-height: 1.1; color: var(--text-1); font-feature-settings: 'tnum'; }
  .wc-sub { font-size: 12px; color: var(--text-2); }
  .wc-track { height: 8px; border-radius: 4px; background: var(--surface-2); overflow: hidden; }
  .wc-fill { display: block; height: 100%; background: var(--accent); border-radius: 4px; }
  .wc-note { margin: 0; font-size: 13px; color: var(--text-2); line-height: 1.4; }
  .wc-note strong { color: var(--text-1); }
  .wc-note.warn strong { color: #b45309; }

  .wc-bars { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 6px; }
  .wc-col { display: flex; flex-direction: column; align-items: center; gap: 4px; min-width: 0; }
  .wc-num { font-size: 11px; font-weight: 600; color: var(--text-2); font-feature-settings: 'tnum'; }
  .wc-bar-area { height: 72px; width: 100%; display: flex; align-items: flex-end; }
  .wc-bar {
    position: relative; width: 100%; min-height: 4px;
    border-radius: 6px; overflow: hidden; box-sizing: border-box;
  }
  .wc-past { background: var(--surface-2); }
  .wc-today, .wc-future { border: 1.5px dashed var(--text-3); }
  .wc-today { border-color: var(--accent); }
  .wc-bar.unlogged { border: 1.5px dashed var(--border); background: none; }
  .wc-bar-fill {
    position: absolute; left: 0; right: 0; bottom: 0;
    background: var(--accent);
  }
  .wc-bar-fill.over { background: #d97706; }
  .wc-dow { font-size: 11px; font-weight: 700; color: var(--text-3); }
  .wc-col.today .wc-dow { color: var(--accent); }
  .wc-foot { margin: 0; font-size: 12px; color: var(--text-3); }
  .wc-foot strong { color: var(--text-2); font-feature-settings: 'tnum'; }
</style>
