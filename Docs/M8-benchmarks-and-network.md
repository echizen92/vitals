# M8 Benchmarks and network test

## Benchmark
- Stages: CPU one core and all cores (xorshift + float multiply-add, fixed chunks, each stage capped at 2 s so the
  whole run stays under 10 s), one Metal compute pass (kernel compiled at runtime, 4 M floats × 256 FMA loops,
  reported in GFLOPS), storage write and read of a 128 MB temp file with `F_NOCACHE`, deleted afterwards.
- Refused at serious or critical heat ("a hot phone only measures throttling"); records thermal state at start and
  end and Low Power Mode.
- **Baselines**: `benchmark-baselines.json` ships **empty**. Vitals publishes no expected range it has not measured;
  every result currently says "No baseline for this model yet, so these are raw results". Ranges get added from
  real runs (start with the Duo). A below-range result becomes an attention finding in Memory & performance.
- Result feeds the report and the diagnosis.

## Network test
- One constant (`NetworkTestConfig.base`, default `https://speed.cloudflare.com`; `/__down?bytes=` and `/__up`).
- Confirmation dialog first ("uses about 30 MB… nothing about you or this phone is sent").
- DNS: domain-lookup phase of the first request on a fresh ephemeral session (`URLSessionTaskMetrics`).
  Latency: median request→first-byte of 8 zero-byte requests; jitter: mean difference between consecutive probes.
  Download 25 MB, upload 5 MB, Mbit/s. Errors listed per stage.
- This is the only network use in the app.

## Verified, and how
- Tests: hot refusal, a scaled-down run producing all stages without a baseline, CPU time cap, verdict against a
  range, latency median/jitter maths, Mbit/s maths.
- Simulator (Debug): benchmark ran, all five stages reported, "no baseline" note shown (`Docs/screens/m8-benchmark.png`).
  It took 10.9 s in the unoptimised build, which led to the time cap. Numbers are the Mac's, not a phone's.
- Simulator: network test ran against Cloudflare over the Mac's Wi-Fi: 916 / 198 Mbit/s, 49.7 ms latency,
  12 ms DNS (`m8-network.png`). That is the Mac's connection.

## Not verified (needs the Duo)
- Benchmark numbers and duration on the Duo (Release build), heat added by a run, and the first baseline ranges.
- Network test on cellular, with Low Data Mode and with a VPN.
