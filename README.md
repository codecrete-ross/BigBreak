# BigBreak

A simple break timer for World of Warcraft. Displays break timers sent by DBM and BigWigs without requiring either addon.

## Features

- **Break timer bar** with color-coded countdown: green > 3 min, yellow ≤ 3 min, red ≤ 1 min
- **DBM and BigWigs interop** — receives break timers from both addons
- **1-minute warning** with sound alert
- **Break complete notification** with raid warning frame message
- **Configurable bar size** — Small, Medium, or Big
- **Persists across /reload** — timer picks up where it left off
- **Sync protocol** — recovers timers from group members after /reload
- **Movable and lockable** bar with right-click to cancel
- **Settings panel** via `/bb` with sound, flash, lock, and bar size options
- **Addon compartment button** for quick settings access

## How To Use

1. In a raid or party, type `/break 5` to start a 5-minute break timer
2. All BigBreak, DBM, and BigWigs users in your group will see the timer
3. The bar counts down with color changes and a 1-minute warning
4. Type `/break 0` to cancel, or right-click the bar

## Requirements

None. No libraries, no dependencies.

## Slash Commands

- `/break N` — Start a break timer (N minutes, 1-60)
- `/break 0` — Cancel active timer
- `/bb` — Open settings panel
- `/bb test` — Show a test break timer
- `/bb reset` — Reset all settings to defaults

## Install

Install via [CurseForge](https://www.curseforge.com/wow/addons/bigbreak), or copy the `BigBreak` folder into your `Interface/AddOns/` directory.
