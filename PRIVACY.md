# Privacy Policy

MachineContext is private, but **private repository does not mean secret storage**.

## Never collect or commit

- passwords or recovery codes;
- API keys or access tokens;
- OAuth access/refresh tokens;
- GitHub, Vercel, Supabase, OpenAI, Codex, or other service credentials;
- `.env` values;
- SSH/private signing keys;
- cookies, browser session data, browser profiles, or password-manager data;
- proxy subscription URLs, proxy credentials, node passwords, or complete proxy configs;
- authentication-file contents such as Codex auth data;
- shell history;
- raw process command lines or process-owner dumps;
- raw active network-connection dumps;
- arbitrary contents of user documents;
- raw whole-disk / Everything discovery result lists;
- complete Registry/config/dotfile dumps.

It is acceptable to record that a sensitive file exists and, when useful, its normalized path. Do not read or commit its secret contents.

## Discovery is local-first

Broad discovery may temporarily see many paths/candidates. These results belong only in ignored `.local/` staging/cache and must be reduced to approved normalized facts before publication.

Filesystem/index discovery should search metadata/fingerprints, not arbitrary file contents. A broad path list is never itself a publishable artifact.

## Configuration parsing

When a config file must be inspected, use a source-specific allowlist parser. Extract only fields with explicit value to MachineContext.

Examples:

- MCP config: server name/scope may be useful; env/token/credential values are forbidden;
- Git remote: sanitize userinfo, embedded credentials, query parameters, and secret-bearing fragments before storage;
- npm/pip/custom registries: store safe host/“custom configured” state, not credential-bearing URLs;
- `.env*`: filename/path/exists only;
- proxy config: client/state/local ports may be useful, subscription/node/credential content is forbidden.

Do not solve privacy by first copying full config and hoping a final regex removes everything.

## AI configuration projections

`context/configs/` stores sanitized projections of frequently edited AI harness configuration. The boundary between a projection and a "sanitized-looking raw config dump" is:

1. **Per-field allowlist by source**: every supported tool has an explicit parser whose provider/model sections allowlist safe fields individually; unknown fields are dropped by default and recorded by name only (`unprojected_keys`). The shared "strip secret-looking keys" walker is defense in depth, never the primary boundary. There is no generic "read any JSON/YAML and strip secret-looking keys" sanitizer as the privacy mechanism.
2. **Credential values never survive**: a credential field may be published only as an environment-variable **name** (`credentialEnvName` in place, `credential_env_names` at profile level) or, per D039, as a `credential_configured: true` boolean when the credential is stored opaquely and no env-var name exists. Values that are not environment-variable-shaped are dropped and recorded in `redactions` with the source path.
3. **Credential-named keys never survive**: published projections must not contain keys such as `apiKey`, `token`, `secret`, `apiKeyPool`; the validator rejects them (`config_sensitive_key`).
4. **URLs are sanitized**: userinfo, query strings, and fragments are stripped from base URLs; credential-bearing query parameters cause redaction records.
5. **MCP arguments are checked as a sequence**: credential flags (`--token`, `--api-key`, `-H`/`--header`, ...) are dropped together with the argv they consume, `flag=value` forms individually; MCP `env` is reduced to variable names only.
6. **Sensitive files stay opaque**: auth DBs, `.env`, credential stores, session/history/usage databases are recorded as normalized path + exists + role only.
7. **Freshness is explicit**: a projection whose source files are confirmed absent is marked `source_state: stale`, never silently presented as current config; parser failures keep the previous record untouched.

## Environment variables

Collectors may record approved environment-variable **names or existence** when useful. They must not dump values by default.

## Paths

Prefer environment-variable-normalized paths:

- `%USERPROFILE%`
- `%APPDATA%`
- `%LOCALAPPDATA%`
- `%PROGRAMDATA%`

Literal non-user paths such as `D:\Tools\...` or `E:\Dev\...` are acceptable when relevant to installation/development planning.

Do not record hostname, external IP history, hardware serials, user SID, or similar identifiers merely because they are easy to query.

## Collection policy

Use an allowlist. Every new collector/provider should answer:

1. Why is this fact useful to an AI decision?
2. Can the same goal be achieved without reading sensitive content?
3. Is this a candidate-only fact or should it be persistent canonical context?
4. Is the fact stable enough to store?
5. Can it be represented without a secret/private value?
6. What raw data does the provider touch, and where is that raw data discarded?

If the answer is unclear, do not collect it automatically.

## Review before publication/push

Validation should happen **before canonical publication**, not only before Git push. It should reject or flag:

- common token/key/credential patterns;
- `.env` or auth file contents;
- PEM/private keys;
- suspicious credential-bearing URLs;
- unexpected raw config/Registry/process/network payloads;
- files from `.local/`, raw/capture/log directories;
- unexpected binaries or large files;
- literal user-specific paths that should have been normalized.

A later pre-commit/push scan remains defense in depth.
