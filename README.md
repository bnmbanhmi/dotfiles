# macOS Dotfiles & Personal Utilities

Centralized management repository for personal macOS configurations and custom menu bar utilities.

---

## Repository Structure

```text
~/Git/dotfiles/
├── config/
│   ├── ghostty/
│   │   └── config             # Ghostty terminal configuration
│   ├── hammerspoon/
│   │   └── init.lua           # Hammerspoon (Slidepad clone, Webviews, Hotkeys)
│   └── warp/
│       └── settings.toml      # Warp terminal settings
│
├── tools/
│   ├── menubar-notes/
│   │   └── menubar_notes.swift # Native Swift MenuBar notepad (liquid glass UI)
│   └── pomodoro/
│       ├── smart_pomodoro.swift    # Countdown Pomodoro timer with auto-breaks
│       └── stopwatch_pomodoro.swift # Count-up Stopwatch timer with lap exports
│
├── bin/                       # Output directory for compiled binaries
├── install.sh                 # 1-click symlink & setup script
└── README.md
```

---

## Quick Setup

Clone the repository and run the setup script:

```bash
# Link all config files to system locations (~/.config, ~/.hammerspoon, ~/.warp)
./install.sh

# Or link and compile all Swift menu bar utilities at once:
./install.sh --build
```

---

## Managed Configurations

| App | Repo Path | System Path |
| :--- | :--- | :--- |
| **Hammerspoon** | `config/hammerspoon/init.lua` | `~/.hammerspoon/init.lua` |
| **Ghostty** | `config/ghostty/config` | `~/.config/ghostty/config`<br>`~/Library/Application Support/com.mitchellh.ghostty/config` |
| **Warp** | `config/warp/settings.toml` | `~/.warp/settings.toml` |

---

## Custom Menu Bar Utilities (`tools/`)

### 1. MenuBar Notes (`tools/menubar-notes/menubar_notes.swift`)
* A persistent menu bar notepad without timer or pomodoro clutter.
* Automatically displays the first line of your note directly in the macOS menu bar.
* Saves content persistently in `UserDefaults`.
* Features a translucent liquid glass popover panel.

**Run in background:**
```bash
nohup ./menubar_notes > /dev/null 2>&1 &
```

### 2. Smart Pomodoro (`tools/pomodoro/smart_pomodoro.swift`)
* Traditional Pomodoro timer that counts down from a specified number of minutes.
* Automatically schedules a break when the focus session ends.
* Run with custom minutes:
```bash
nohup ./smart_pomodoro 25 > /dev/null 2>&1 &
```

### 3. Stopwatch Pomodoro (`tools/pomodoro/stopwatch_pomodoro.swift`)
* Stopwatch-style timer counting up from `00:00`.
* Lap recording with decimal hours formatting (`1.5` instead of `01:30`).
* Quick clipboard export for focus tracking.
```bash
nohup ./stopwatch_pomodoro > /dev/null 2>&1 &
```

---

## Backward Compatibility Note
`~/Git/pomodoro` is preserved as a symbolic link pointing to `~/Git/dotfiles` to ensure any running processes, legacy scripts, or shortcuts continue functioning seamlessly.
