# Nested verifier failure semantics

## Scope

Reconciliation now handles verification-bearing nested observed objects conservatively. A nested `unverified` or `stale` result keeps prior facts such as `present` and installation paths while updating the verification state and current probe status. A nested `verified-absent` result retains the prior object under `last_known`.

This closes the Visual Studio Native Desktop workload timeout case: a successful Visual Studio installation probe can coexist with a timed-out workload probe without erasing the last known workload evidence or turning the timeout into an absence claim.

## Verification

Added regression coverage for nested workload timeout and verified absence. The existing top-level provider-failure and curated-ownership tests remain unchanged.
