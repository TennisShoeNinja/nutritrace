<script>
  /**
   * "This week" page of the Diary's Today/Week card (fork addition): what's
   * left of the week, today's plan, a bar per day, then the coach summary:
   * macro averages vs goals, protein days, and the week's weight. Data and
   * math come from TodayWeekCard.svelte, src/lib/weekly-budget.js and
   * src/lib/week-summary.js.
   */
  export let p;          // weekPlan() result
  export let isos = [];  // the week's 7 dates
  export let summary = null;  // weekNutrition() result
  export let weight = null;   // weekWeight() result
  export let unit = 'lb';     // weight unit
  export let sample = false;  // weights are dev fixtures

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
  const fmtW = v => v == null ? '—' : v.toFixed(1);
  const fmtChange = v => v == null ? null : (v > 0 ? '+' : v < 0 ? '−' : '±') + Math.abs(v).toFixed(1);
  $: proteinByIso = new Map((summary?.proteinDays || []).map(d => [d.iso, d.hit]));
  $: weightByIso = new Map((weight?.days || []).map(d => [d.iso, d.value]));
  $: unitLabel = unit === 'lb' ? 'lb' : 'kg';
  $: hasWeights = (weight?.count || 0) > 0;

  $: usedPct = Math.min(100, Math.round(p.eaten / Math.max(p.budget, 1) * 100));
  $: inWeek = p.todayPlan != null;
  $: weekOver = p.days.every(d => d.state === 'past');
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
        {#if summary}
          {@const hit = proteinByIso.get(b.iso)}
          <span class="wc-pmark" class:hit={hit === true} class:miss={hit === false}
            role="img" aria-label={hit == null ? `${b.iso}: protein not counted` : `${b.iso}: protein goal ${hit ? 'hit' : 'missed'}`}></span>
        {/if}
        {#if hasWeights}
          <span class="wc-w" class:none={weightByIso.get(b.iso) == null}>{fmtW(weightByIso.get(b.iso))}</span>
        {/if}
      </div>
    {/each}
  </div>
  {#if summary || weight}
    <p class="wc-legend">
      <span class="wc-pmark hit" aria-hidden="true"></span> protein goal hit
      {#if hasWeights}· weight in {unitLabel}{/if}
    </p>
  {/if}

  {#if !weekOver}<!-- a finished week lands at what was eaten: shown above -->
    <p class="wc-foot">On plan the week lands at <strong>{fmt(p.landing)}</strong></p>
  {/if}

  {#if summary}
    <div class="wc-sec">
      <div class="wc-sec-head">
        <span class="wc-sec-title">Daily average</span>
        <span class="wc-sec-meta">{summary.n} {summary.n === 1 ? 'day' : 'days'} logged{p.todayPlan != null ? ' · today not counted' : ''}</span>
      </div>
      {#if summary.n}
        <div class="wc-macros">
          {#each summary.rows as r (r.key)}
            <span class="wc-m-label">{r.label}</span>
            <span class="wc-m-val">{fmt(r.value)}<small>{r.unit === 'g' ? ' g' : ''}</small></span>
            <span class="wc-m-goal">{#if r.goal != null}{r.min ? 'min' : 'max'} {fmt(r.goal)}{/if}</span>
            <span class="wc-m-ok material-symbols-rounded" class:ok={r.ok === true} class:miss={r.ok === false}
              aria-label={r.ok == null ? '' : r.ok ? 'on goal' : 'off goal'}>{r.ok == null ? '' : r.ok ? 'check_circle' : 'error'}</span>
          {/each}
        </div>
        <p class="wc-line">Protein goal hit <strong>{summary.proteinHit} of {summary.n}</strong> {summary.n === 1 ? 'day' : 'days'}</p>
      {:else}
        <p class="wc-line">No finished days logged yet.</p>
      {/if}
    </div>
  {/if}

  {#if weight}
    <div class="wc-sec">
      <div class="wc-sec-head">
        <span class="wc-sec-title">Weight{#if sample} <em class="wc-sample">sample data</em>{/if}</span>
        <span class="wc-sec-meta">{weight.count} {weight.count === 1 ? 'weigh-in' : 'weigh-ins'}</span>
      </div>
      {#if !hasWeights}
        <p class="wc-line">No weigh-ins this week{weight.prevAvg != null ? ` · last week ${fmtW(weight.prevAvg)} ${unitLabel}` : ''}.</p>
      {:else}
      <div class="wc-wsum">
        <div class="wc-wcell">
          <span class="wc-wbig">{fmtW(weight.avg)}<small>&nbsp;{unitLabel}</small></span>
          <span class="wc-wcap">7-day average</span>
        </div>
        <div class="wc-wcell">
          <span class="wc-wbig">{fmtChange(weight.change) ?? '—'}<small>&nbsp;{unitLabel}</small></span>
          <span class="wc-wcap">{weight.prevAvg != null ? `vs last week (${fmtW(weight.prevAvg)})` : 'vs last week'}</span>
        </div>
      </div>
      {/if}
    </div>
  {/if}
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
  .wc-bar-area { height: 60px; width: 100%; display: flex; align-items: flex-end; }
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

  /* Coach summary: protein marks and weights under each day, then averages. */
  .wc-pmark {
    width: 9px; height: 9px; border-radius: 50%; box-sizing: border-box;
    display: inline-block; flex: none;
  }
  .wc-pmark.hit { background: var(--success); }
  .wc-pmark.miss { border: 1.5px solid var(--warning); }
  .wc-w { font-size: 11px; font-weight: 600; color: var(--text-1); font-feature-settings: 'tnum'; letter-spacing: -0.2px; }
  .wc-w.none { color: var(--text-3); font-weight: 400; }
  .wc-legend { margin: -6px 0 0; font-size: 11px; color: var(--text-3); display: flex; align-items: center; gap: 4px; justify-content: center; }

  .wc-sec { border-top: 1px solid var(--border); padding-top: 8px; display: flex; flex-direction: column; gap: 4px; }
  .wc-sec-head { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
  .wc-sec-title { font-size: 13px; font-weight: 600; color: var(--text-1); }
  .wc-sec-meta { font-size: 12px; color: var(--text-3); }
  .wc-sample { font-style: normal; font-size: 11px; font-weight: 600; color: var(--warning); margin-left: 4px; }
  .wc-macros {
    display: grid; grid-template-columns: 1fr auto auto 20px;
    column-gap: 12px; row-gap: 2px; align-items: center;
  }
  .wc-m-label { font-size: 13px; color: var(--text-2); }
  .wc-m-val { font-size: 14px; font-weight: 700; color: var(--text-1); text-align: right; font-feature-settings: 'tnum'; }
  .wc-m-val small { font-size: 11px; font-weight: 500; color: var(--text-2); }
  .wc-m-goal { font-size: 12px; color: var(--text-3); text-align: right; font-feature-settings: 'tnum'; }
  .wc-m-ok { font-size: 18px; line-height: 1; }
  .wc-m-ok.ok { color: var(--success); }
  .wc-m-ok.miss { color: var(--warning); }
  .wc-line { margin: 0; font-size: 13px; color: var(--text-2); }
  .wc-line strong { color: var(--text-1); }
  .wc-wsum { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  .wc-wcell { display: flex; flex-direction: column; gap: 1px; }
  .wc-wbig { font-size: 20px; font-weight: 700; color: var(--text-1); font-feature-settings: 'tnum'; line-height: 1.15; }
  .wc-wbig small { font-size: 12px; font-weight: 500; color: var(--text-2); }
  .wc-wcap { font-size: 12px; color: var(--text-3); }
  .wc-foot strong { color: var(--text-2); font-feature-settings: 'tnum'; }
</style>
