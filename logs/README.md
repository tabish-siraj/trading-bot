# Logs

The canonical project logs live in `PROJECT_MAP.md`:

- **Decision Log** — Section 8
- **Trial Log** — Section 9

Do not create parallel copies here; one source of truth. This folder is for
machine-written logs.

## holdout_access.log

Append-only record of every read of `data/holdout/`. Written only by
`scripts/holdout_eval.py`. Format: one line per access, with UTC timestamp,
author/process, reason, and the data range touched.

If an entry appears that you did not expect, stop and investigate: the holdout
may have been contaminated.
