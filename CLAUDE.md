# BigBreak

A simple break timer with no external dependencies.

## Project Structure

- `BigBreak.toc` — addon metadata, interface version
- `BigBreak.lua` — all addon code (single file)
- `logo.png` — branding for GitHub/CurseForge (not shipped in CF package)
- `.pkgmeta` — CurseForge packager config (ignore list, changelog source)
- `CHANGELOG.md` — curated changelog used by CurseForge via `.pkgmeta` changelog-from directive

## Release Workflow

1. Make changes and deploy to WoW folder for testing:
   ```
   cp BigBreak.toc BigBreak.lua "/g/Battle.net Games/World of Warcraft/_retail_/Interface/AddOns/BigBreak/"
   ```
2. Test in-game with `/reload`
3. **Wait for user confirmation before committing**
4. Add entry to `CHANGELOG.md`
5. Commit, push, tag, create GitHub release
6. CurseForge picks up the tag automatically via webhook

Never push, tag, or release untested changes. Copy to the WoW folder and stop — wait for testing.

## WoW Addon Conventions

- Target current retail patch only
- No global namespace pollution — use `local` variables; only globals are SavedVariables (`BigBreakDB`, `BigBreakCharDB`) and `BigBreak_OnAddonCompartmentClick`
- No frames created in hot paths — lazy-create once, reuse
- No external dependencies or libraries
- Classic support: code is gated for older clients (Settings API, MenuUtil, C_AddOns). Only flavor-specific TOC files are needed to publish for Classic.

## Key APIs

- `C_ChatInfo.SendAddonMessage` / `C_ChatInfo.RegisterAddonMessagePrefix` — addon communication
- D5 protocol: `"PlayerName-Realm\t1\tBT\t<seconds>"` — DBM/BigWigs break timer format
- `Settings.RegisterCanvasLayoutCategory` — settings panel (retail 10.0+)
- `MenuUtil.CreateRadioMenu` — bar size dropdown (retail 11.0+)
- `GetServerTime()` — timer persistence across /reload
- `FlashClientIcon()` — taskbar flash on break start/complete

## Verified Protocol Sources

- DBM break timer: `G:\Battle.net Games\World of Warcraft\_retail_\Interface\AddOns\DBM-Core\modules\objects\UserTimers.lua`
- DBM message format: `G:\Battle.net Games\World of Warcraft\_retail_\Interface\AddOns\DBM-Core\modules\objects\AddonComms.lua`
- BigWigs break timer: `G:\Battle.net Games\World of Warcraft\_retail_\Interface\AddOns\BigWigs_Plugins\Break.lua`
- BigWigs D5 compat: `G:\Battle.net Games\World of Warcraft\_retail_\Interface\AddOns\BigWigs\Loader.lua`

## Changelog Style

Changelog entries must be written for end users, not developers. Use plain language that describes what changed from the user's perspective. No technical jargon, internal function names, or implementation details.

## Publishing

- GitHub: https://github.com/codecrete-ross/BigBreak
- CurseForge: auto-packaged via webhook on tag push
- License: All Rights Reserved
- `.pkgmeta` excludes: `CLAUDE.md`, `PLAN.md`, `.claude`, `README.md`, `logo.png`, `.gitignore`

## Slash Commands

- `/break N` — start a break timer (N minutes, 1-60)
- `/break 0` — cancel active timer
- `/bb` — open settings panel
- `/bb test` — 15-second test break timer
- `/bb reset` — reset all settings and bar position to defaults

## Compatibility & Versioning

Before making any update, verify:

1. **WoW client version** — run `/dump (select(4, GetBuildInfo()))` in-game to get the current Interface number. Update `## Interface:` in the TOC if it's changed. **Never guess from patch numbers** — always verify against the live client.
2. **DBM/BigWigs protocol** — if either addon updates, verify the D5 BT message format hasn't changed by reading their source from the installed addon folders listed above.

The `## Interface` version in the TOC should always match the current live retail patch to avoid the "out of date" addon warning in-game.
