# 2026-08-26 — G1 semantic review draft

This pass continued Initial Audit Closure with read-only evidence only. The review draft is kept in ignored `.local/g2-semantic-review.json`; no project lifecycle, AI-tool role, proxy-primary, or installation convention was written to canonical `curated` fields.

## Evidence collected

- `ProxyLens` has a recent commit on `feat/phase-3b-pre-ui-readiness`; `Morpho` has tracked local changes; the two `agent-bridge-legacy` roots have recent maintenance-shaped commits. These are review signals, not automatic lifecycle decisions.
- Persistent Windows host resolution found no `pnpm` candidate. A bounded set of known pnpm paths was also absent, so pnpm remains `unverified`, not `verified-absent`.
- `E:\FlClash\FlClash-0.8.96` exists with `pubspec.yaml`, no `.git` directory, and no top-level executable. It remains a manifest-only candidate and was not promoted.
- The current `127.0.0.1:7988` listener is associated with `FlClashCore`; historical ports remain unresolved hints. No proxy policy or primary-client meaning was inferred.

The next G2 action still requires explicit confirmation of the suggested project lifecycle buckets, AI-tool roles, proxy semantics, and installation/update conventions.
