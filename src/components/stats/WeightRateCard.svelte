<!--
  WeightRateCard.svelte: rate of loss, week over week (fork addition).

  The last five Sunday-to-Saturday weeks: average weight, the change from
  the week before in weight and as % of body weight, and the week's average
  kcal. Each change is coloured against a target band (Settings key
  weightRateBand, default 0.5-1.0% a week), green inside, amber outside.
  Weight is read the same way the Statistics weight chart reads it:
  Withings, then the server-merged Fitbit / Health Connect / Google Health
  rows, then local Health Connect (Android), then the Diary's body stats.
  Logic lives in src/lib/weight-trend.js.
-->
<script>
  import { onMount } from 'svelte';
  import { DB, localDateStr } from '../../lib/db.js';
  import { NtApi } from '../../lib/api.js';
  import { Nutrition } from '../../lib/nutrition.js';
  import { readBodyStat } from '../../lib/body-stats-unit.js';
  import { isAndroid } from '../../lib/platform.js';
  import { weightUnit, lengthUnit, withingsEnabled, fitbitFamilyEnabled, healthConnectEnabled } from '../../stores/settings.js';
  import { weeklyTrend, fixtureDays, normalizeBand, BAND_SETTING_KEY, DEFAULT_BAND } from '../../lib/weight-trend.js';

  const WEEKS = 5;
  let days = null;          // [{ date, weight, kcal }]
  let sample = false;       // showing fixture data because there are no weigh-ins yet
  let band = normalizeBand(DB.getSetting(BAND_SETTING_KEY, DEFAULT_BAND));
  let editing = false;
  let draftMin = band.min, draftMax = band.max;

  $: unit = $weightUnit === 'kg' ? 'kg' : 'lb';
  $: today = localDateStr();
  $: trend = days ? weeklyTrend(days, { today, weeks: WEEKS, band, unit }) : null;

  async function load() {
    const end = new Date();
    const from = new Date(); from.setDate(from.getDate() - (WEEKS + 1) * 7 - 7);
    const fromStr = localDateStr(from), toStr = localDateStr(end);
    let withings = {}, fitbit = {}, hc = {};
    try { if ($withingsEnabled) withings = await NtApi.get(`/api/wellness/withings/data?from=${fromStr}&to=${toStr}`); } catch {}
    try { if ($fitbitFamilyEnabled) fitbit = await NtApi.get(`/api/wellness/fitbit/data?from=${fromStr}&to=${toStr}`); } catch {}
    if ($healthConnectEnabled && isAndroid) {
      try {
        const { dbGetWellnessGrouped } = await import('../../lib/db-native.js');
        hc = await dbGetWellnessGrouped(fromStr, toStr, 'health_connect');
      } catch {}
    }
    const all = await NtApi.getAllDiary().catch(() => []);
    const diary = Object.fromEntries((all || []).map(e => [e.date, e]));

    const rows = [];
    for (const d = new Date(from); d <= end; d.setDate(d.getDate() + 1)) {
      const date = localDateStr(d);
      const entry = diary[date];
      const kg = withings[date]?.weight_kg?.value ?? fitbit[date]?.weight_kg ?? hc[date]?.weight_kg ?? null;
      let weight = kg != null ? (unit === 'lb' ? kg * 2.20462 : kg) : null;
      if (weight == null && entry) weight = readBodyStat(entry.body_stats || entry.bodyStats || {}, 'weight', $weightUnit, $lengthUnit);
      const items = entry?.items || [];
      const kcal = items.length ? Math.round(Nutrition.sum(items.map(i => Nutrition.calculate(i))).calories || 0) : null;
      rows.push({ date, weight: Number.isFinite(Number(weight)) && weight ? Number(weight) : null, kcal });
    }
    // Until real weigh-ins exist (fewer than two weeks with any), show labelled sample data.
    const probe = weeklyTrend(rows, { today, weeks: WEEKS, unit });
    sample = probe.weeks.filter(w => w.avgWeight != null).length < 2;
    days = sample ? fixtureDays(today, unit === 'kg' ? { startWeight: 119, perWeek: 0.8 } : {}) : rows;
  }
  onMount(load);

  function saveBand() {
    const next = normalizeBand({ min: draftMin, max: draftMax });
    band = next;
    draftMin = next.min; draftMax = next.max;
    DB.setSetting(BAND_SETTING_KEY, next);
    editing = false;
  }

  const fmtRange = (w) => {
    const o = { month: 'short', day: 'numeric' };
    return new Date(w.start + 'T12:00:00').toLocaleDateString(undefined, o);
  };
  const sign = (x) => (x > 0 ? '+' : x < 0 ? '−' : '±');
  const abs = (x) => Math.abs(x);
  const label = { in: 'On pace', fast: 'Too fast', slow: 'Too slow' };
</script>

<div class="card wr">
  <div class="wr-head">
    <div>
      <div class="wr-title">Rate of loss</div>
      <div class="wr-sub">Weekly averages, Sunday to Saturday</div>
    </div>
    <button class="wr-band" on:click={() => { editing = !editing; draftMin = band.min; draftMax = band.max; }}
            aria-expanded={editing} title="Change the target band">
      Target {band.min.toFixed(1)}–{band.max.toFixed(1)}%/wk
    </button>
  </div>

  {#if editing}
    <form class="wr-edit" on:submit|preventDefault={saveBand}>
      <label>Lose at least <input type="number" step="0.05" min="0" bind:value={draftMin} inputmode="decimal" />%</label>
      <label>at most <input type="number" step="0.05" min="0" bind:value={draftMax} inputmode="decimal" />% a week</label>
      <button class="btn btn-sm" type="submit">Save</button>
    </form>
  {/if}

  {#if sample}
    <div class="wr-sample">Sample data: not enough weigh-ins yet. This fills in after two weeks of weighing.</div>
  {/if}

  {#if trend}
    <div class="wr-table" role="table" aria-label="Weekly weight change">
      <div class="wr-row wr-th" role="row">
        <span role="columnheader">Week of</span>
        <span role="columnheader">Avg</span>
        <span role="columnheader">Change</span>
        <span role="columnheader">kcal/day</span>
      </div>
      {#each [...trend.weeks].reverse() as w (w.start)}
        <div class="wr-row" role="row">
          <span role="cell" class="wr-wk">
            {fmtRange(w)}{#if w.partial}<em> · so far</em>{/if}
            <small>{w.weighIns} weigh-in{w.weighIns === 1 ? '' : 's'}</small>
          </span>
          <span role="cell" class="wr-num">{w.avgWeight != null ? w.avgWeight.toFixed(1) : '—'}</span>
          <span role="cell" class="wr-num wr-chg {w.status || ''}">
            {#if w.change != null}
              {sign(w.change)}{abs(w.change).toFixed(1)} {unit}
              <small>{sign(-w.lossPct)}{abs(w.lossPct).toFixed(2)}% · {label[w.status]}</small>
            {:else}—{/if}
          </span>
          <span role="cell" class="wr-num">{w.avgKcal != null ? w.avgKcal.toLocaleString() : '—'}</span>
        </div>
      {/each}
    </div>

    {#if trend.tdee}
      <div class="wr-tdee">
        Estimated burn <b>{trend.tdee.toLocaleString()} kcal/day</b>
        <small>from logged kcal and the weekly change, full weeks only. Rough: it is only as good as the logging.</small>
      </div>
    {/if}
  {:else}
    <div class="wr-sub">Loading…</div>
  {/if}
</div>

<style>
  .wr { padding: 14px 16px; margin-top: 12px; }
  .wr-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 8px; margin-bottom: 10px; }
  .wr-title { font-size: 15px; font-weight: 600; color: var(--text-1); }
  .wr-sub { font-size: 12px; color: var(--text-3); }
  .wr-band {
    font-size: 12px; font-weight: 600; color: var(--text-2); white-space: nowrap;
    background: var(--surface-2); border: 1px solid var(--border); border-radius: 999px;
    padding: 4px 10px; cursor: pointer;
  }
  .wr-edit { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; font-size: 13px; color: var(--text-2); margin-bottom: 10px; }
  .wr-edit input { width: 60px; margin: 0 4px; }
  .wr-sample {
    font-size: 12px; color: var(--text-2); background: var(--surface-2);
    border-left: 3px solid var(--warning); padding: 6px 10px; border-radius: 4px; margin-bottom: 10px;
  }
  .wr-row { display: grid; grid-template-columns: 1.3fr 0.8fr 1.4fr 0.9fr; gap: 8px; align-items: center; padding: 7px 0; border-top: 1px solid var(--border); }
  .wr-th { border-top: none; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .05em; color: var(--text-3); padding-top: 0; }
  .wr-th span:not(:first-child), .wr-num { text-align: right; }
  .wr-wk { font-size: 13px; color: var(--text-1); }
  .wr-wk em { font-style: normal; color: var(--text-3); }
  .wr-row small { display: block; font-size: 11px; color: var(--text-3); font-weight: 500; }
  .wr-num { font-size: 14px; font-weight: 600; color: var(--text-1); font-variant-numeric: tabular-nums; }
  .wr-chg.in, .wr-chg.in small { color: var(--success); }
  .wr-chg.fast, .wr-chg.slow, .wr-chg.fast small, .wr-chg.slow small { color: var(--warning); }
  .wr-tdee { margin-top: 10px; padding-top: 10px; border-top: 1px solid var(--border); font-size: 13px; color: var(--text-2); }
  .wr-tdee b { color: var(--text-1); }
  .wr-tdee small { display: block; font-size: 11px; color: var(--text-3); margin-top: 2px; }
</style>
