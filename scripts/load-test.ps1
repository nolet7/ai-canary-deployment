param(
  [Parameter(Mandatory=$true)][string]$Url,
  [int]$Requests = 500,
  [int]$Concurrency = 25
)

$ErrorActionPreference = "Stop"

$script = @"
const http = require('http');
const https = require('https');
const { performance } = require('perf_hooks');

const url = new URL(process.argv[2]);
const total = Number(process.argv[3]);
const concurrency = Number(process.argv[4]);
const client = url.protocol === 'https:' ? https : http;
let started = 0;
let completed = 0;
let ok = 0;
let failed = 0;
const latencies = [];
const t0 = performance.now();

function one() {
  if (started >= total) return;
  started++;
  const s = performance.now();
  const req = client.get(url, res => {
    res.resume();
    res.on('end', () => {
      const ms = performance.now() - s;
      latencies.push(ms);
      if (res.statusCode >= 200 && res.statusCode < 400) ok++; else failed++;
      done();
    });
  });
  req.setTimeout(10000, () => {
    req.destroy(new Error('timeout'));
  });
  req.on('error', () => {
    failed++;
    latencies.push(performance.now() - s);
    done();
  });
}

function done() {
  completed++;
  if (started < total) one();
  if (completed === total) report();
}

function percentile(p) {
  const sorted = [...latencies].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))] || 0;
}

function report() {
  const seconds = (performance.now() - t0) / 1000;
  console.log(JSON.stringify({
    url: url.toString(),
    requests: total,
    concurrency,
    ok,
    failed,
    rps: Number((total / seconds).toFixed(2)),
    latency_ms: {
      p50: Number(percentile(0.50).toFixed(1)),
      p95: Number(percentile(0.95).toFixed(1)),
      p99: Number(percentile(0.99).toFixed(1))
    }
  }, null, 2));
}

for (let i = 0; i < Math.min(concurrency, total); i++) one();
"@

$tmp = New-TemporaryFile
$js = "$tmp.js"
Move-Item $tmp $js
Set-Content -Path $js -Value $script -Encoding ascii
node $js $Url $Requests $Concurrency
Remove-Item $js

