# 2026-08-26 — proxy listener evidence

The read-only listener check found `127.0.0.1:7988` owned by a process named `FlClashCore`, whose parent was `FlClashHelperService.exe`. The matching service was `Running` with `Auto` start mode. No listener was present on the historical `10808`, `10100`, or `18080` ports. Executable paths were not available without expanding permissions.

This strengthens the evidence that the current local proxy path is associated with the FlClash family and its helper service, but it does not prove the user's intended primary client, the relationship to `E:\FlClash\FlClash-0.8.96`, or any proxy policy. The evidence remains in ignored `.local/audit-closure.json`; no canonical project promotion or curated network constraint was made.
