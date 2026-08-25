# Tests

V1 tests should prioritize behavior that keeps MachineContext maintainable:

- parser/normalizer behavior from captured non-sensitive fixtures;
- stable IDs and stable output ordering;
- repeated no-change runs produce no semantic diff;
- absent commands fail soft;
- path normalization works for `%USERPROFILE%`, `%APPDATA%`, and other approved roots;
- broken references are detected;
- privacy validation catches representative secret patterns and forbidden files;
- `CURRENT.md` rendering is deterministic.

Do not commit real secrets or raw personal machine dumps as fixtures.
