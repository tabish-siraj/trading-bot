# Runtime

Record here where the system actually runs. This is a Phase 0b deliverable and a
prerequisite for Phases 4–5. Fill in every field; "TBD" is a blocker, not a value.

## MT5 runtime

- Hosting: macOS workstation (running now). Method (Wine / CrossOver / VM): TBD
- OS version: TBD
- MT5 terminal build: TBD
- Broker server: TBD
- Account number (demo): TBD
- Account type: TBD (raw-spread vs standard; commission vs spread)
- Symbol names as seen in Market Watch: TBD (e.g. XAUUSD, XAUUSDm, suffixes)

## Build and test

- How MQL5 source gets into the terminal: repo `mt5/experts/` mirrors `MQL5/Experts/`; copy preserving the `risk/` folder
- Compiler: MetaEditor version TBD
- Strategy Tester: real ticks available? TBD
- Tick history depth available: TBD

## Source layout

The EA includes `"risk/RiskAdapter.mqh"` relative to its own folder. Keep the
`risk/` subfolder next to `GoldTrendPullbackEA.mq5` when copying into MT5.

## Build check performed (2026-11-24)

- Tool: bundled Wine + `metaeditor64.exe` from `/Applications/MetaTrader 5.app`
- `mt5/experts/risk/RiskLayerTests.mq5`: **0 errors, 0 warnings**
- `mt5/experts/GoldTrendPullbackEA.mq5`: **0 errors, 0 warnings**
- Compiled test EA staged in the terminal at `MQL5/Experts/_agent_build/risk/RiskLayerTests.ex5`
- Runtime tests still to run: attach `RiskLayerTests` to any chart and read the
  Experts log for `RISK TESTS PASSED` (it places no orders and unloads itself).

## Transfer path

- Code lives in this repo on macOS; how is it synced to the Windows runtime? TBD
- Any files that must never be synced automatically: `config/risk_global.yaml` is hash-checked (see Phase 7).

## Notes

- MT5 is Windows-native. Do not assume it can run directly on the macOS workstation.
