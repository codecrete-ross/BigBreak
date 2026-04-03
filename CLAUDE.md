# BigBreak

A simple break timer with no external dependencies.

## Conventions

- Lua style: `local` everything, no globals except SavedVariables (`BigBreakDB`, `BigBreakCharDB`) and `BigBreak_OnAddonCompartmentClick`
- Single-file architecture — all code lives in `BigBreak.lua`
- WoW API target: Retail 12.x (Midnight)
- Testing: manual in-game — `/break 1` for a 1-minute test, `/bb test` for a 15-second test
- No external dependencies or libraries
- CurseForge packaging via `.pkgmeta` with `changelog-from: CHANGELOG.md`
