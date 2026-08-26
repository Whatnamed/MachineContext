# Published verification heartbeat boundary

## Finding

The latest successful Full publish completed after 12:24 UTC, while committed `context/status.json` still exposed `published_verification.verified_at=2026-08-26T11:47:50.1729074Z`. The reconciliation code preserved the timestamp whenever mode and provider summary were unchanged, but it had no way to distinguish a no-publish proposal from a real publication.

## Change

`Update-McPublishedStatus` now accepts an explicit publish-heartbeat switch. `scripts/sync.ps1` enables it only when `-NoPublish` is absent. Read-only/no-publish proposals therefore remain byte-stable for the existing heartbeat, while a successful real publish refreshes only the compact publication timestamp.

## Evidence

- `20260826-122404825-1301ed83`: Full publish, validation passed, provider aggregate `success`.
- Before this change: committed heartbeat `2026-08-26T11:47:50.1729074Z`; closure projection `2026-08-26T12:22:41.6862960Z`.
- Added regression coverage for preservation during no-publish reconciliation and refresh during explicit publish.
