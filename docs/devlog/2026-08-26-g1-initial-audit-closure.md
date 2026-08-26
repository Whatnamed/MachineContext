# 2026-08-26 — G1 initial audit closure pass

## Scope

Ran the first real-machine Full Audit after G0 correctness hardening and the explicit staged canonical cleanup. All collection remained read-only; no dependency, software, PATH, proxy, registry, or system changes were performed.

## Published result

- Full publish run: `20260826-074010175-785a708c`.
- Validation passed with no errors or warnings.
- Provider aggregate was `partial`: structured providers succeeded, host-authoritative tools had limited failures, bounded discovery reached its budget, and optional Everything was unavailable because no existing `es.exe` was found.
- Canonical project registry contains eight verified Git roots. The old Flutter SDK-root record was demoted and its exact staged project file deletion was published atomically.
- Canonical software keeps `pnpm` as `unverified`; it does not publish a fallback process-only path or infer absence.

## Repeatability

- Full repeat run `20260826-074109151-a38ffe15` produced an exact byte match for all 19 canonical/Markdown proposal files after stable-key ordering was fixed and published.
- Quick runs `20260826-074204377-50eb17a1` and `20260826-074228160-729c59e9` produced identical canonical context except for expected `status.json` verification metadata; neither was published.
- `.local/audit-closure.json` records historical bootstrap-hint evidence, unresolved items, and the zero-conflict result without reading or storing credential contents.

## Follow-up

G1 remains partial until project lifecycle/purpose, bridge and proxy semantics, installation/update ownership, and remaining unverified candidates are reviewed. These are semantic decisions and should move to G2 only after explicit confirmation.
