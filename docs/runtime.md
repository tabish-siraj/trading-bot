# Runtime

Record here where the system actually runs. This is a Phase 0b deliverable and a
prerequisite for Phases 4–5. Fill in every field; "TBD" is a blocker, not a value.

## MT5 runtime

- Hosting: TBD (Windows VM / Windows VPS / other)
- OS version: TBD
- MT5 terminal build: TBD
- Broker server: TBD
- Account number (demo): TBD
- Account type: TBD (raw-spread vs standard; commission vs spread)
- Symbol names as seen in Market Watch: TBD (e.g. XAUUSD, XAUUSDm, suffixes)

## Build and test

- How MQL5 source gets to the terminal: TBD (shared folder / repo clone on Windows / manual copy)
- Compiler: MetaEditor version TBD
- Strategy Tester: real ticks available? TBD
- Tick history depth available: TBD

## Transfer path

- Code lives in this repo on macOS; how is it synced to the Windows runtime? TBD
- Any files that must never be synced automatically: `config/risk_global.yaml` is hash-checked (see Phase 7).

## Notes

- MT5 is Windows-native. Do not assume it can run directly on the macOS workstation.
