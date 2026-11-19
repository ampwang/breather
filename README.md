# Breather

A small RSIGuard-style break reminder for macOS 13+, living in the menu bar.

## What it does
- **Micro-breaks**: by default 20 s after every 10 min of active use.
- **Rest breaks**: by default 5 min after 50 min of active use, **or** 4,000 keystrokes, **or** 1,500 clicks, whichever comes first.
- **30 s warning**: a small panel in the top-right corner, so you can finish what you're typing.
- **Lock screen**: during a break, every display is covered with a countdown. The Dock, menu bar and Cmd-Tab are disabled.
- **Postpone**: 2 postpones per break by default, 5 min each. You can choose to allow skipping breaks (it's off by default).
- **Natural breaks**: if you're away from the keyboard and mouse for a full break length, the timer resets on its own.
- **Pause** for 30 min, 1 h or 2 h (for meetings or screen sharing). Today's active time, keys and clicks are shown in the menu.

Breather only *counts* keys. It never looks at which keys you press, and nothing leaves your Mac.

## Build & install
```bash
xcode-select --install        # first time only (Apple's command line tools)
cd Breather
chmod +x build.sh && ./build.sh
rm -rf /Applications/Breather.app && cp -R build/Breather.app /Applications/
open /Applications/Breather.app
```

## Permissions
On first launch, macOS will ask you to allow **Accessibility** (System Settings → Privacy & Security → Accessibility). Turn on Breather there. Breather needs this to count keystrokes and clicks. Time-based breaks work even without it.

**After every rebuild**, macOS sees a "new" app. Remove Breather from the Accessibility list with the **–** button, then add it back.

## Escape hatch
If something ever goes wrong while the screen is locked, press **Cmd-Option-Esc** (Force Quit) and quit Breather.

## Code map
| File | Purpose |
|---|---|
| `BreakScheduler.swift` | The timing engine: active time, limits, natural breaks, postpone/skip |
| `ActivityMonitor.swift` | Counts keys and clicks, and reads system idle time |
| `Overlay.swift` | The full-screen break lock and the warning panel |
| `Views.swift` | The menu bar dropdown and the Settings window |
| `Prefs.swift` | Settings keys and their defaults |
