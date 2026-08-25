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
- proxy subscription URLs, proxy credentials, or node passwords;
- authentication-file contents such as Codex auth data;
- arbitrary contents of user documents.

It is acceptable to record that a sensitive file exists and, when useful, its normalized path. Do not read or commit its contents.

## Environment variables

Collectors may record approved environment-variable **names** when useful. They must not dump environment-variable values by default.

## Paths

Prefer environment-variable-normalized paths:

- `%USERPROFILE%`
- `%APPDATA%`
- `%LOCALAPPDATA%`
- `%PROGRAMDATA%`

Literal non-user paths such as `D:\Tools\...` or `E:\Dev\...` are acceptable when they are relevant to installation and development planning.

## Collection policy

Use an allowlist. Every new collector should answer:

1. Why is this fact useful to an AI decision?
2. Can the same goal be achieved without reading sensitive content?
3. Is the fact stable enough to store?
4. Can it be safely represented without a secret value?

If the answer is unclear, do not collect it automatically.

## Review before push

A sync process should perform privacy checks before commit/push, including common secret patterns, `.env` files, token-like values, private keys, and unexpected large/binary files.
