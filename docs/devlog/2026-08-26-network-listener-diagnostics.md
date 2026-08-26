# Network listener local diagnostics

## Change

The `network-local-services` collector now records process ownership for the existing allowlisted local listeners in the provider's `local` payload. The collection layer writes that payload only to `.local/local-diagnostics.json`.

Each local diagnostic retains the port, normalized local address, loopback/local-machine scope, and best-effort process name. Process access failure remains `null`; the collector does not read command lines or executable contents, and it does not infer absence from missing ownership data.

Canonical `context/network.json` remains limited to observed listener presence and address scope. No proxy purpose, curated meaning, or historical endpoint was promoted by this change.

## Verification

- `tests/run-tests.ps1`: all 18 tests passed.
- Full no-publish runs `20260826-081001841-d32bcd95` and `20260826-081117426-cc4c4568`: overall `success`, validation passed, and all 19 proposal targets were byte-equal across the repeat and to current canonical files.
- Quick no-publish runs `20260826-081251697-223a9409` and `20260826-081319357-9467421c`: overall `success`, validation passed, canonical context was equal except expected status timestamp; local listener diagnostics were equal.
- Current read-only evidence records `127.0.0.1:7988` owned by `FlClashCore`; the executable path remains unavailable. Ports `10808`, `10100`, and `18080` had no current listener and remain unresolved historical hints rather than absence claims.
