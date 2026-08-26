# Current install-location rendering

- `CURRENT.md` now falls back from an executable to verified `install_location`, `install.root`, or Visual Studio `installation_path` metadata.
- This keeps the compact AI entry view useful for package/IDE entities that have a verified installation but no single executable path.
- The change is presentation-only; it does not broaden collection scope or write curated semantics.
