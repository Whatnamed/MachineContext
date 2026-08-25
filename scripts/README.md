# Local maintenance scripts

The first local implementation should add small PowerShell scripts here.

Target commands:

- `collect.ps1` — read-only collection of approved machine facts;
- `verify.ps1` — verify existing records and mark stale/unavailable facts;
- `render.ps1` — regenerate `CURRENT.md`;
- `validate.ps1` — schema/data/privacy checks;
- `sync.ps1` — orchestrate collect -> verify -> validate -> render -> diff.

Do not build a GUI before this workflow works reliably on the real machine.
