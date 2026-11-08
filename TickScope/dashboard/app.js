'use strict';

// Every number on the page comes from these files (written by the engine and Spark jobs).
const DATA = '../results/';
const FILES = {
  shallow: 'bench_v1_v2_shallow.json',
  deep: 'bench_v1_v2_deep.json',
  micro: 'microbench_v1_v2.json',
  pipeline: 'pipeline.json',
  spark: 'spark_bench.json',
  stats: 'stats.json',
  fills: 'fills.json',
  market: 'market_5m.json',
  hist: 'returns_hist.json',
  replay: 'book_replay.json',
  ingest: 'ingest_report.json',
};

// ---- helpers ---------------------------------------------------------------------------
const $ = (id) => document.getElementById(id);
const tok = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
const M = (x) => (x / 1e6).toFixed(1) + 'M';
const int = (x) => Math.round(x).toLocaleString('en-US');
const fx = (x, d = 2) => Number(x).toFixed(d);
const usd = (ticks) => (ticks / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const btc = (lots) => (lots / 1e5).toFixed(4);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const dayFmt = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
const timeFmt = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'UTC' });

function table(head, rows) {
  return '<div class="tscroll"><table><thead><tr>' + head.map((h) => `<th>${h}</th>`).join('') + '</tr></thead><tbody>' +
    rows.map((r) => '<tr>' + r.map((c) => `<td>${c}</td>`).join('') + '</tr>').join('') + '</tbody></table></div>';
}

function legend(el, items) {
  el.innerHTML = items.map(([label, color]) => `<span><i style="background:${color}"></i>${esc(label)}</span>`).join('');
}

function kpi(v, l, d) {
  return `<div class="kpi"><div class="v">${v}</div><div class="l">${l}</div>${d ? `<div class="d">${d}</div>` : ''}</div>`;
}

// ---- charts ----------------------------------------------------------------------------
const builders = [];
const live = [];
function chart(id, build) {
  builders.push({ id, build });
}
function renderCharts() {
  while (live.length) live.pop().destroy();
  Chart.defaults.font.family = 'system-ui, -apple-system, "Segoe UI", sans-serif';
  Chart.defaults.font.size = 12;
  Chart.defaults.color = tok('--muted');
  Chart.defaults.animation = false;
  Chart.defaults.layout.padding = { left: 4, right: 8 };
  for (const { id, build } of builders) live.push(new Chart($(id), build()));
}

function axis(extra = {}) {
  return {
    grid: { color: tok('--grid'), drawTicks: false },
    border: { color: tok('--axis') },
    ticks: { color: tok('--muted'), padding: 6 },
    ...extra,
  };
}

function tooltip(label) {
  return {
    backgroundColor: tok('--surface'),
    titleColor: tok('--text'),
    bodyColor: tok('--text-2'),
    borderColor: tok('--border'),
    borderWidth: 1,
    padding: 10,
    displayColors: true,
    boxPadding: 4,
    callbacks: { label },
  };
}

const bar = (label, data, color, extra = {}) => ({
  label, data, backgroundColor: color, borderRadius: 4, borderSkipped: 'start', maxBarThickness: 36, ...extra,
});

// Hairline reference lines (e.g. the ±1.96/√n band) drawn under the data.
const refLines = {
  id: 'refLines',
  beforeDatasetsDraw(c, _args, opts) {
    if (!opts || !opts.values) return;
    const { ctx, chartArea: a, scales: { y } } = c;
    ctx.save();
    ctx.strokeStyle = opts.color;
    ctx.lineWidth = 1;
    for (const v of opts.values) {
      const py = Math.round(y.getPixelForValue(v)) + 0.5;
      ctx.beginPath(); ctx.moveTo(a.left, py); ctx.lineTo(a.right, py); ctx.stroke();
    }
    ctx.restore();
  },
};

// Vertical cursor for the replay price chart.
const cursor = {
  id: 'cursor',
  afterDatasetsDraw(c, _args, opts) {
    if (!opts || opts.x == null) return;
    const { ctx, chartArea: a, scales: { x } } = c;
    const px = Math.round(x.getPixelForValue(opts.x)) + 0.5;
    ctx.save();
    ctx.strokeStyle = opts.color; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(px, a.top); ctx.lineTo(px, a.bottom); ctx.stroke();
    ctx.restore();
  },
};

// ---- sections --------------------------------------------------------------------------
function kpis(d) {
  const v2 = d.shallow.engines.v2.throughputEventsPerSec;
  const deepX = d.deep.engines.v2.throughputEventsPerSec / d.deep.engines.v1.throughputEventsPerSec;
  const csv = d.spark.variants[0].medianSec;
  const pruned = d.spark.variants.find((v) => v.variant.startsWith('3')).medianSec;
  const p99 = d.shallow.engines.v2.latencyNs.limit_rest.p99;
  $('kpis').innerHTML =
    kpi(M(v2), 'events/s, engine v2', `real Nov 5 flow, ${int(d.shallow.events)} events`) +
    kpi(fx(deepX) + '×', 'v2 vs v1 on a deep book', `${int(d.deep.avgLevels)} price levels on average`) +
    kpi(`${int(p99)} ns`, 'p99 to rest a limit order', 'v2; 41 ns timer resolution') +
    kpi(fx(csv / pruned, 1) + '×', 'Spark: pruned Parquet vs CSV', 'this run; 31.1× in an earlier session (noisy CSV baseline)') +
    kpi(M(d.ingest.rowsRead), 'trades ingested and checked', `${int(d.ingest.rowsRead - d.ingest.rowsKept)} rejected`);
}

function engine(d) {
  const v1c = tok('--deemph'), v2c = tok('--series-1');
  const sc = [d.shallow, d.deep];
  const labels = sc.map((s) => (s.scenario === 'deep' ? 'Deep book' : 'Default book') + ` (${int(s.avgLevels)} levels)`);
  legend($('lg-throughput'), [['v1 std::map', v1c], ['v2 flat array', v2c]]);
  chart('c-throughput', () => ({
    type: 'bar',
    data: {
      labels,
      datasets: [
        bar('v1 std::map', sc.map((s) => s.engines.v1.throughputEventsPerSec), tok('--deemph')),
        bar('v2 flat array', sc.map((s) => s.engines.v2.throughputEventsPerSec), tok('--series-1')),
      ],
    },
    options: {
      maintainAspectRatio: false,
      plugins: { legend: { display: false }, tooltip: tooltip((c) => ` ${c.dataset.label}: ${M(c.raw)} events/s`) },
      scales: { x: axis({ grid: { display: false } }), y: axis({ beginAtZero: true, ticks: { color: tok('--muted'), callback: (v) => M(v) } }) },
    },
  }));
  $('n-throughput').textContent = sc
    .map((s) => `${s.scenario === 'deep' ? 'Deep' : 'Default'}: ${fx(s.engines.v2.throughputEventsPerSec / s.engines.v1.throughputEventsPerSec)}× (${int(s.fills)} identical fills)`)
    .join(' · ');

  const ops = [['limit_rest', 'Rest limit'], ['limit_cross', 'Limit that trades'], ['market', 'Market'], ['ioc', 'IOC'], ['cancel_hit', 'Cancel']];
  legend($('lg-latency'), [['v1 std::map', v1c], ['v2 flat array', v2c]]);
  chart('c-latency', () => ({
    type: 'bar',
    data: {
      labels: ops.map((o) => o[1]),
      datasets: [
        bar('v1 std::map', ops.map((o) => d.deep.engines.v1.latencyNs[o[0]].p99), tok('--deemph')),
        bar('v2 flat array', ops.map((o) => d.deep.engines.v2.latencyNs[o[0]].p99), tok('--series-1')),
      ],
    },
    options: {
      maintainAspectRatio: false,
      plugins: { legend: { display: false }, tooltip: tooltip((c) => ` ${c.dataset.label}: ${int(c.raw)} ns p99`) },
      scales: { x: axis({ grid: { display: false } }), y: axis({ beginAtZero: true, ticks: { color: tok('--muted'), callback: (v) => v + ' ns' } }) },
    },
  }));

  const med = Object.fromEntries(d.micro.benchmarks.filter((b) => b.aggregate_name === 'median').map((b) => [b.run_name, b]));
  const rows = [['AddCancel/10', 'Add + cancel, 10 levels/side'], ['AddCancel/1000', 'Add + cancel, 1,000 levels/side'],
    ['AddAndFill/10', 'Add + market fill, 10 levels'], ['AddAndFill/1000', 'Add + market fill, 1,000 levels'],
    ['ReplaySynthetic', 'Synthetic 1 h replay']].map(([k, label]) => {
    const a = med['v1/' + k], b = med['v2/' + k];
    return [label, `${fx(a.real_time)} ${a.time_unit}`, `${fx(b.real_time)} ${b.time_unit}`, fx(a.real_time / b.real_time, 1) + '×'];
  });
  $('t-micro').innerHTML = table(['Benchmark', 'v1', 'v2', 'Speedup'], rows);
}

function pipeline(d) {
  const names = { single_thread: 'Single thread (no queue)', spsc_batch64: 'SPSC queue, batch pop 64', spsc_pop1: 'SPSC queue, pop 1', mutex_pop1: 'Mutex queue, pop 1' };
  const order = ['single_thread', 'spsc_batch64', 'spsc_pop1', 'mutex_pop1'];
  chart('c-pipeline', () => ({
    type: 'bar',
    data: { labels: order.map((k) => names[k]), datasets: [bar('Throughput', order.map((k) => d.pipeline.modes[k].medianEventsPerSec), tok('--series-1'))] },
    options: {
      indexAxis: 'y', maintainAspectRatio: false,
      plugins: { legend: { display: false }, tooltip: tooltip((c) => ` ${M(c.raw)} events/s`) },
      scales: { x: axis({ beginAtZero: true, ticks: { color: tok('--muted'), callback: (v) => M(v) } }), y: axis({ grid: { display: false }, ticks: { color: tok('--text-2') } }) },
    },
  }));
}

function spark(d) {
  const short = ['CSV, gzip re-parsed', 'Parquet, timestamp filter', 'Parquet + partition pruning', '+ cache', '+ 8 shuffle partitions'];
  const vs = d.spark.variants;
  chart('c-spark', () => ({
    type: 'bar',
    data: { labels: short, datasets: [bar('Median runtime', vs.map((v) => v.medianSec), tok('--series-1'))] },
    options: {
      indexAxis: 'y', maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: tooltip((c) => {
          const v = vs[c.dataIndex];
          return [` ${fx(v.medianSec)} s median (${fx(v.speedupVsCsv, 1)}× vs CSV)`, ` ${v.filesRead} files read`];
        }),
      },
      scales: { x: axis({ type: 'logarithmic', ticks: { color: tok('--muted'), callback: (v) => ([1, 2, 5, 10, 20, 50, 100].includes(v) ? v + ' s' : '') } }), y: axis({ grid: { display: false }, ticks: { color: tok('--text-2') } }) },
    },
  }));
  const csv = vs[0], pr = vs[2];
  $('n-spark').textContent = `Partition pruning reads ${pr.filesRead} of ${csv.filesRead} files. Caching cost ${fx(vs[3].medianCacheBuildSec)} s to build and did not pay off over two queries. ` +
    `Shuffle tuning had no effect: adaptive execution coalesced the shuffle to ${vs[0].q2ShufflePartitionsAfterAqe} partition in every variant.`;
  $('t-spark').innerHTML = table(['Variant', 'Runs (s)', 'Median', 'vs CSV', 'Cache build', 'Queries', 'Files', 'Shuffle parts after AQE'],
    vs.map((v, i) => [short[i], v.runs.map((r) => fx(r.totalSec)).join(' · '), fx(v.medianSec), fx(v.speedupVsCsv, 1) + '×',
      v.cache ? fx(v.medianCacheBuildSec) : '—', fx(v.medianQueriesSec), v.filesRead, v.q2ShufflePartitionsAfterAqe]));
}

function market(d) {
  const bars = d.market.bars; // [tsSec, open, high, low, close, vwap, volume, buyVolume]
  const days = [];
  for (let t = Math.ceil(bars[0][0] / 86400) * 86400; t <= bars[bars.length - 1][0]; t += 86400) days.push(t);
  const dayTicks = (s) => { s.ticks = days.map((v) => ({ value: v })); };
  chart('c-price', () => ({
    type: 'line',
    data: { datasets: [{ label: 'Close', data: bars.map((b) => ({ x: b[0], y: b[4] })), borderColor: tok('--series-1'), borderWidth: 2, pointRadius: 0, pointHoverRadius: 4, tension: 0 }] },
    options: {
      maintainAspectRatio: false, parsing: false, normalized: true,
      interaction: { mode: 'index', intersect: false },
      plugins: { legend: { display: false }, tooltip: { ...tooltip((c) => ` close ${c.raw.y.toLocaleString('en-US')} USDT`), callbacks: { title: (it) => timeFmt.format(new Date(it[0].raw.x * 1000)) + ' UTC', label: (c) => ` close ${c.raw.y.toLocaleString('en-US')} USDT` } } },
      scales: {
        x: axis({ type: 'linear', afterBuildTicks: dayTicks, ticks: { color: tok('--muted'), callback: (v) => dayFmt.format(new Date(v * 1000)) } }),
        y: axis({ ticks: { color: tok('--muted'), callback: (v) => v.toLocaleString('en-US') } }),
      },
    },
  }));
  const hours = [];
  for (let i = 0; i < bars.length; i += 12) {
    const slice = bars.slice(i, i + 12);
    hours.push({ x: slice[0][0], y: slice.reduce((a, b) => a + b[6], 0) });
  }
  chart('c-volume', () => ({
    type: 'bar',
    data: { datasets: [{ label: 'Volume', data: hours, backgroundColor: tok('--series-1'), borderRadius: 2, barPercentage: 0.9, categoryPercentage: 1 }] },
    options: {
      maintainAspectRatio: false, parsing: false,
      plugins: { legend: { display: false }, tooltip: { ...tooltip(), callbacks: { title: (it) => timeFmt.format(new Date(it[0].raw.x * 1000)) + ' UTC', label: (c) => ` ${c.raw.y.toFixed(1)} BTC` } } },
      scales: {
        x: axis({ type: 'linear', offset: false, afterBuildTicks: dayTicks, ticks: { color: tok('--muted'), callback: (v) => dayFmt.format(new Date(v * 1000)) } }),
        y: axis({ beginAtZero: true }),
      },
    },
  }));
}

function stats(d) {
  const s = d.stats, r = s.returns, p = s.imbalancePredictsReturn;
  $('stat-tiles').innerHTML =
    kpi(fx(r.excessKurtosis), 'excess kurtosis', 'normal distribution = 0') +
    kpi(`${r.beyond4Sigma} vs ${fx(r.normalExpectedBeyond4Sigma, 1)}`, 'moves beyond 4σ', 'observed vs normal') +
    kpi(fx(p.hacT), 'HAC t-stat, imbalance → next return', `naive t ${fx(p.naiveT)}; r² = ${fx(100 * p.r * p.r, 2)}%`) +
    kpi(`${int(r.n)}`, '1-minute returns', `${s.from} → ${s.to}`);

  const h = d.hist.bins;
  legend($('lg-hist'), [['Observed', tok('--series-1')], ['Normal distribution', tok('--text-2')]]);
  chart('c-hist', () => ({
    type: 'bar',
    data: {
      labels: h.map((b) => `${b.lo}σ`),
      datasets: [
        { type: 'line', label: 'Normal distribution', data: h.map((b) => b.normal), borderColor: tok('--text-2'), borderWidth: 2, pointRadius: 0, tension: 0.3, order: 0 },
        bar('Observed', h.map((b) => b.observed || null), tok('--series-1'), { borderRadius: 2, barPercentage: 0.95, categoryPercentage: 1, order: 1 }),
      ],
    },
    options: {
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: { legend: { display: false }, tooltip: { ...tooltip(), callbacks: { title: (it) => { const b = h[it[0].dataIndex]; return `${b.lo}σ to ${b.hi}σ`; }, label: (c) => ` ${c.dataset.label}: ${c.raw == null ? 0 : c.dataset.type === 'line' ? fx(c.raw, 3) : int(c.raw)}` } } },
      scales: {
        x: axis({ grid: { display: false }, ticks: { color: tok('--muted'), autoSkip: false, maxRotation: 0, callback: (_v, i) => (i % 4 === 0 ? h[i].lo + 'σ' : '') } }),
        y: axis({ type: 'logarithmic', min: 0.5, ticks: { color: tok('--muted'), callback: (v) => ([1, 10, 100, 1000].includes(v) ? int(v) : '') } }),
      },
    },
  }));

  const acf = s.acf, absAcf = s.absAcf, band = 1.96 / Math.sqrt(r.n);
  legend($('lg-acf'), [['Returns', tok('--series-1')], ['|Returns|', tok('--series-2')]]);
  chart('c-acf', () => ({
    type: 'bar',
    data: { labels: acf.map((a) => `lag ${a.lag}`), datasets: [bar('Returns', acf.map((a) => a.rho), tok('--series-1'), { borderSkipped: false }), bar('|Returns|', absAcf.map((a) => a.rho), tok('--series-2'), { borderSkipped: false })] },
    options: {
      maintainAspectRatio: false,
      plugins: { legend: { display: false }, refLines: { values: [band, -band], color: tok('--muted') }, tooltip: tooltip((c) => ` ${c.dataset.label}: ρ = ${fx(c.raw, 4)}`) },
      scales: { x: axis({ grid: { display: false } }), y: axis({ ticks: { color: tok('--muted'), callback: (v) => fx(v, 1) } }) },
    },
    plugins: [refLines],
  }));
  $('n-acf').textContent = `Hairlines mark ±1.96/√n = ±${fx(band, 4)}. Returns stay near zero, so direction is unpredictable. |Returns| sit at ${fx(Math.min(...absAcf.map((a) => a.rho)), 2)}–${fx(Math.max(...absAcf.map((a) => a.rho)), 2)}: volatility clusters.`;
}

function fills(d) {
  const f = d.fills;
  const names = { real_market: 'Real market orders', real_ioc: 'Real IOC orders', synthetic_limit: 'Synthetic limits' };
  const keys = ['real_market', 'real_ioc', 'synthetic_limit'];
  chart('c-fillrate', () => ({
    type: 'bar',
    data: { labels: keys.map((k) => names[k]), datasets: [bar('Fill rate', keys.map((k) => 100 * f.fillRates[k].fillRate), tok('--series-1'))] },
    options: {
      indexAxis: 'y', maintainAspectRatio: false,
      plugins: { legend: { display: false }, tooltip: tooltip((c) => { const k = keys[c.dataIndex]; return [` ${fx(c.raw)}% of quantity filled`, ` ${fx(100 * f.fillRates[k].fullyFilledShare, 1)}% of orders fully filled`]; }) },
      scales: { x: axis({ beginAtZero: true, max: 100, ticks: { color: tok('--muted'), callback: (v) => v + '%' } }), y: axis({ grid: { display: false }, ticks: { color: tok('--text-2') } }) },
    },
  }));
  const s5 = f.spreads['5s'];
  $('t-spreads').innerHTML = table(['Taker', 'Fills', 'Effective', 'Realized', 'Impact'],
    keys.map((k) => [names[k], int(s5[k].fills), fx(s5[k].effectiveBp, 3), fx(s5[k].realizedBp, 3), fx(s5[k].impactBp, 3)]));
  const slip = (obj, label) => Object.keys(obj).sort().map((k) => [label, names[k], int(obj[k].n), fx(obj[k].mean, 3), fx(obj[k].p10, 3), fx(obj[k].p50, 3), fx(obj[k].p90, 3), fx(obj[k].p99, 3)]);
  $('t-slippage').innerHTML = table(['Versus', 'Taker', 'Executions', 'Mean', 'p10', 'p50', 'p90', 'p99'],
    [...slip(f.slippageVsVwapBp, '1m VWAP'), ...slip(f.slippageVsPrintBp, 'Real print')]);
}

// ---- order-book replay ------------------------------------------------------------------
function replay(d) {
  const r = d.replay, frames = r.frames, SHOW = 10;
  const start = new Date(r.fromSec * 1000);
  // Stable bar scale across frames: 95th percentile of displayed level sizes.
  const sizes = frames.flatMap((f) => [...f.bids.slice(0, SHOW), ...f.asks.slice(0, SHOW)].map((l) => l[1])).sort((a, b) => a - b);
  const scale = sizes[Math.floor(sizes.length * 0.95)] || 1;
  const slider = $('rp-slider');
  slider.max = frames.length - 1;
  const sweptFrames = frames.filter((f) => !f.bids.length || !f.asks.length).length;
  $('rp-note').textContent = `${timeFmt.format(start)} UTC + 60 s · ${int(r.fills.length)} engine fills · seed ${r.seed} · playback 4× real time. ` +
    `In ${sweptFrames} of ${frames.length} frames one side of the synthetic book was empty, swept by real flow.`;

  // Five columns: bid size | bid bar | price | ask bar | ask size. Sizes have their own
  // columns, so a long bar can never cover its label at any width.
  const row = (side, lvl) => {
    const w = Math.min(100, (100 * lvl[1]) / scale);
    const barCell = `<div class="${side}"><div class="bar" style="width:${w}%"></div></div>`;
    return side === 'bid'
      ? `<div class="lrow"><span class="qb">${btc(lvl[1])}</span>${barCell}<div class="px">${usd(lvl[0])}</div><div></div><span></span></div>`
      : `<div class="lrow"><span></span><div></div><div class="px">${usd(lvl[0])}</div>${barCell}<span class="qa">${btc(lvl[1])}</span></div>`;
  };
  const filler = '<div class="lrow"><span></span><div></div><div class="px"></div><div></div><span></span></div>';

  let priceChart = null;
  const series = {
    real: r.realPricePath.map((p) => ({ x: p[0] / 1e6, y: p[1] / 100 })),
    bid: frames.map((f) => ({ x: f.t / 1e6, y: f.bids.length ? f.bids[0][0] / 100 : null })),
    ask: frames.map((f) => ({ x: f.t / 1e6, y: f.asks.length ? f.asks[0][0] / 100 : null })),
  };
  chart('c-replay-price', () => ({
    type: 'line',
    data: {
      datasets: [
        { label: 'Real Binance price', data: series.real, borderColor: tok('--deemph'), borderWidth: 2, pointRadius: 0, stepped: true },
        { label: 'Engine best bid', data: series.bid, borderColor: tok('--series-1'), borderWidth: 2, pointRadius: 0, spanGaps: false },
        { label: 'Engine best ask', data: series.ask, borderColor: tok('--series-2'), borderWidth: 2, pointRadius: 0, spanGaps: false },
      ],
    },
    options: {
      maintainAspectRatio: false, parsing: false,
      interaction: { mode: 'nearest', axis: 'x', intersect: false },
      plugins: {
        legend: { display: true, position: 'bottom', labels: { color: tok('--text-2'), boxWidth: 10, boxHeight: 10, useBorderRadius: true, borderRadius: 3 } },
        cursor: { x: 0, color: tok('--text-2') },
        tooltip: { ...tooltip(), callbacks: { title: (it) => `+${fx(it[0].raw.x)} s`, label: (c) => ` ${c.dataset.label}: ${c.raw.y == null ? '—' : c.raw.y.toLocaleString('en-US', { minimumFractionDigits: 2 })}` } },
      },
      scales: { x: axis({ type: 'linear', min: 0, max: r.seconds, ticks: { color: tok('--muted'), callback: (v) => v + ' s' } }), y: axis({ ticks: { color: tok('--muted'), callback: (v) => v.toLocaleString('en-US') } }) },
    },
    plugins: [cursor],
  }));

  function draw(i) {
    const f = frames[i];
    const asks = f.asks.slice(0, SHOW).reverse();
    const bids = f.bids.slice(0, SHOW);
    let html = '<div class="ladder-head"><span>bid size (BTC)</span><span>price</span><span>ask size (BTC)</span></div>';
    html += filler.repeat(SHOW - asks.length) + asks.map((l) => row('ask', l)).join('');
    const spread = f.bids.length && f.asks.length ? `spread ${usd(f.asks[0][0] - f.bids[0][0])}` : (f.bids.length ? 'ask side empty (swept)' : 'bid side empty (swept)');
    html += `<div class="lrow spread"><span></span><div></div><div class="px">${spread}</div><div></div><span></span></div>`;
    html += bids.map((l) => row('bid', l)).join('') + filler.repeat(SHOW - bids.length);
    $('rp-ladder').innerHTML = html;

    const recent = r.fills.filter((x) => x[0] <= f.t).slice(-8).reverse();
    $('rp-tape').innerHTML = recent.map((x) => `<div><span>+${fx(x[0] / 1e6)}s</span><span>${usd(x[1])}</span><span>${btc(x[2])}</span>` +
      `<span class="side"><i style="background:${x[3] === 'B' ? tok('--series-1') : tok('--series-2')}"></i>${x[3] === 'B' ? 'buy' : 'sell'}</span></div>`).join('') ||
      '<div class="empty">no fills yet</div>';
    $('rp-time').textContent = `${fx(f.t / 1e6)} s`;
    priceChart = priceChart || live.find((c) => c.canvas.id === 'c-replay-price');
    if (priceChart) {
      priceChart.options.plugins.cursor.x = f.t / 1e6;
      priceChart.update('none');
    }
  }

  let playing = false, last = 0;
  const stepMs = r.stepUs / 1000 / 4; // 4x real time
  function tick(ts) {
    if (!playing) return;
    if (ts - last >= stepMs) {
      last = ts;
      const next = Number(slider.value) + 1;
      if (next >= frames.length) { playing = false; $('rp-play').textContent = 'Replay'; return; }
      slider.value = next;
      draw(next);
    }
    requestAnimationFrame(tick);
  }
  $('rp-play').addEventListener('click', () => {
    if (!playing && Number(slider.value) >= frames.length - 1) slider.value = 0;
    playing = !playing;
    $('rp-play').textContent = playing ? 'Pause' : 'Play';
    if (playing) requestAnimationFrame(tick);
  });
  slider.addEventListener('input', () => draw(Number(slider.value)));
  return { redraw: () => { priceChart = null; draw(Number(slider.value)); } };
}

// ---- theme -----------------------------------------------------------------------------
function initTheme(onChange) {
  const root = document.documentElement;
  try { const saved = localStorage.getItem('tickscope-theme'); if (saved) root.dataset.theme = saved; } catch { /* storage unavailable */ }
  $('theme-toggle').addEventListener('click', () => {
    const dark = root.dataset.theme ? root.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
    root.dataset.theme = dark ? 'light' : 'dark';
    try { localStorage.setItem('tickscope-theme', root.dataset.theme); } catch { /* ignore */ }
    onChange();
  });
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', onChange);
}

// ---- main ------------------------------------------------------------------------------
async function main() {
  let d;
  try {
    const entries = await Promise.all(Object.entries(FILES).map(async ([k, f]) => {
      const res = await fetch(DATA + f);
      if (!res.ok) throw new Error(`${f}: HTTP ${res.status}`);
      return [k, await res.json()];
    }));
    d = Object.fromEntries(entries);
  } catch (e) {
    const el = $('load-error');
    el.hidden = false;
    el.textContent = `Could not load results (${e.message}). Serve the TickScope folder over HTTP, e.g. "python3 -m http.server" from TickScope/, then open /dashboard/.`;
    return;
  }
  kpis(d);
  engine(d);
  pipeline(d);
  spark(d);
  market(d);
  stats(d);
  fills(d);
  const rp = replay(d);
  renderCharts();
  rp.redraw();
  initTheme(() => { legendsRefresh(d); renderCharts(); rp.redraw(); });
}

// Legend swatches read tokens at build time; refresh them when the theme changes.
function legendsRefresh() {
  legend($('lg-throughput'), [['v1 std::map', tok('--deemph')], ['v2 flat array', tok('--series-1')]]);
  legend($('lg-latency'), [['v1 std::map', tok('--deemph')], ['v2 flat array', tok('--series-1')]]);
  legend($('lg-hist'), [['Observed', tok('--series-1')], ['Normal distribution', tok('--text-2')]]);
  legend($('lg-acf'), [['Returns', tok('--series-1')], ['|Returns|', tok('--series-2')]]);
}

document.addEventListener('DOMContentLoaded', main);
