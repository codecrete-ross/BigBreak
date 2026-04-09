## 1.0.2

- Group members who aren't leaders or assists can no longer cancel break timers via right-click or /break 0
- Timer sync on reload now only accepts timers from leaders and assists

## 1.0.1

- Break timers from non-leaders are now ignored, matching DBM and BigWigs behavior
- Incoming timers are now rejected during boss encounters
- Incoming timer durations are now capped at 60 minutes
- Fixed a rare issue where a same-named player on another realm could have their timers silently ignored

## 1.0.0

- Initial release
- Break timer with DBM and BigWigs interop
- Color-coded bar: green > 3 min, yellow ≤ 3 min, red ≤ 1 min
- 1-minute warning with sound alert
- Break complete notification with raid warning frame message
- Sound and taskbar flash alerts (toggleable)
- Timer persists across /reload and syncs from group members
- Settings panel via /bb
- Addon compartment button for quick settings access
- Right-click bar to cancel
- /break N to send, /break 0 to cancel
