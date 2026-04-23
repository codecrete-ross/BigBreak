# AGENTS.md

This is the canonical shared governance file for repository-level agent guidance.

If guidance applies across tools, write it here first. Keep `CLAUDE.md` as a thin Claude adapter and avoid duplicating shared instructions across files.

## What This Is

BigBreak is a simple World of Warcraft Retail addon: a break timer with DBM and BigWigs interoperability and no external dependencies.

## Project Structure

- `BigBreak.toc` - addon metadata and interface version
- `BigBreak.lua` - all addon code
- `CHANGELOG.md` - curated end-user changelog used by CurseForge
- `.pkgmeta` - CurseForge packager config
- `logo.png` / `logo.tga` - branding assets

## Core Workflow

1. Edit `BigBreak.toc` and `BigBreak.lua`.
2. Deploy to the local WoW addon folder for testing:
   `cp BigBreak.toc BigBreak.lua "/g/Battle.net Games/World of Warcraft/_retail_/Interface/AddOns/BigBreak/"`
3. Test in-game with `/reload`.
4. Wait for user confirmation before committing, pushing, tagging, or releasing.
5. Add a user-facing `CHANGELOG.md` entry before release.

Never push, tag, or release untested changes.

## Key Rules

- Target the current Retail patch only.
- Before compatibility updates, verify the live interface number with `/dump (select(4, GetBuildInfo()))`. Never guess from patch numbers.
- Before protocol-related changes, verify DBM and BigWigs D5 break-timer compatibility against the installed addon sources.
- No global namespace pollution. Use `local` variables; the only globals should be the SavedVariables and `BigBreak_OnAddonCompartmentClick`.
- No frames created in hot paths. Lazy-create once and reuse.
- No external libraries or dependencies.
- Changelog entries must be written for end users, not developers.
- Keep `AGENTS.md`, `CLAUDE.md`, and `.claude/` out of packaged addon artifacts via `.pkgmeta`.

## Key APIs

- `C_ChatInfo.SendAddonMessage` / `C_ChatInfo.RegisterAddonMessagePrefix`
- `Settings.RegisterCanvasLayoutCategory`
- `MenuUtil.CreateRadioMenu`
- `GetServerTime()`
- `FlashClientIcon()`

## Verified Protocol Sources

- `G:\Battle.net Games\World of Warcraft\_retail_\Interface\AddOns\DBM-Core\modules\objects\UserTimers.lua`
- `G:\Battle.net Games\World of Warcraft\_retail_\Interface\AddOns\DBM-Core\modules\objects\AddonComms.lua`
- `G:\Battle.net Games\World of Warcraft\_retail_\Interface\AddOns\BigWigs_Plugins\Break.lua`
- `G:\Battle.net Games\World of Warcraft\_retail_\Interface\AddOns\BigWigs\Loader.lua`

## Slash Commands

- `/break N` - start a break timer
- `/break 0` - cancel the active timer
- `/bb` - open settings
- `/bb test` - 15-second test break timer
- `/bb reset` - reset addon settings and bar position
