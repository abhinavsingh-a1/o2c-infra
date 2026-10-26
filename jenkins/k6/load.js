// Load test of the promotion pipelines (o2c-app ADR-018), run by jenkins/lib.sh k6_run.
// Every virtual user requests each URL of TARGETS in turn, with a short pause.
// Environment: TARGETS (URLs separated by spaces), VUS, DURATION, P95_MS (threshold of
// the 95th percentile in ms), SUMMARY (path of the JSON summary).
// Exit code 99 when a threshold is crossed: p95 >= P95_MS or 1% failed requests or more.
import http from 'k6/http';
import { check, sleep } from 'k6';

const targets = (__ENV.TARGETS || '').split(/\s+/).filter(Boolean);
if (targets.length === 0) {
  throw new Error('TARGETS is empty');
}
const p95 = Number(__ENV.P95_MS || 500);

export const options = {
  vus: Number(__ENV.VUS || 20),
  duration: __ENV.DURATION || '30s',
  thresholds: {
    http_req_duration: [`p(95)<${p95}`],
    http_req_failed: ['rate<0.01'],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'max'],
};

export default function () {
  for (const url of targets) {
    const res = http.get(url, { tags: { name: url } });
    check(res, { 'status 200': (r) => r.status === 200 });
  }
  sleep(0.5);
}

export function handleSummary(data) {
  const m = data.metrics;
  const lines = [
    `targets: ${targets.join(' ')}`,
    `requests: ${m.http_reqs.values.count}, ${m.http_reqs.values.rate.toFixed(1)}/s`,
    `p95: ${m.http_req_duration.values['p(95)'].toFixed(1)} ms (threshold < ${p95} ms)`,
    `errors: ${(m.http_req_failed.values.rate * 100).toFixed(2)}% (threshold < 1%)`,
  ];
  for (const [name, metric] of Object.entries(m)) {
    for (const [threshold, result] of Object.entries(metric.thresholds || {})) {
      lines.push(`${result.ok ? 'PASS' : 'FAIL'} ${name} ${threshold}`);
    }
  }
  const out = { stdout: `${lines.join('\n')}\n` };
  if (__ENV.SUMMARY) {
    out[__ENV.SUMMARY] = JSON.stringify(data, null, 2);
  }
  return out;
}
