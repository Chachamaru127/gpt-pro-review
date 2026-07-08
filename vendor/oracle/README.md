# Oracle reference (read-only)

Upstream: sibling checkout `../oracle` (https://github.com/steipete/oracle)

`scripts/sync-oracle-reference.sh` records:

- `SYNCED_COMMIT` — pinned oracle HEAD
- `SYNCED_AT` / `SYNCED_BRANCH`
- `refs/` — copied excerpts for diff review (not executed)

Do not import oracle as a runtime dependency. Port patterns deliberately into `scripts/pro-review-browser-drive` with fixture tests.
