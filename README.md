# Pomodoro Tools

This repository contains Swift-based menu bar utility applications for macOS.

## Applications

1. **Smart Pomodoro (`smart_pomodoro.swift`)**
   - A traditional Pomodoro timer that counts down from a specified number of minutes.
   - Automatically schedules a break when the focus session ends.
   - Accepts a custom focus duration via command-line arguments.

2. **Stopwatch Pomodoro (`stopwatch_pomodoro.swift`)**
   - A stopwatch-style timer that counts up from `00:00`.
   - Allows recording custom sessions (focus/break) using the **Lap** button.
   - Displays duration history natively as decimal hours (`1.5` instead of `01:30`).
   - Supports copying isolated Focus times or Full times directly to the clipboard.
   - Built natively with the **iOS 26 / macOS 15 Liquid Glass** design framework for advanced translucency.

3. **MenuBar Notes (`menubar_notes.swift`)**
   - A persistent menu bar notepad without timer or pomodoro features.
   - Automatically displays the first line of your note directly in the macOS menu bar.
   - Saves content persistently in `UserDefaults`.
   - Features a translucent liquid glass popover panel.

---

## How to Compile & Run

### 1. Smart Pomodoro

#### Compilation
Compile the Swift source file into a binary executable:
```bash
swiftc -O smart_pomodoro.swift -o smart_pomodoro
```
*(If compiling inside a sandboxed terminal environment, redirect the module cache to prevent permission issues)*:
```bash
swiftc -O smart_pomodoro.swift -module-cache-path ./module_cache -Xcc -fmodules-cache-path=./module_cache -o smart_pomodoro
```

#### Run in Background
To kill any running instances and launch it cleanly in the background (discarding logs to `/dev/null`):
```bash
MINUTES="${1:-25}"

pkill -f "smart_pomodoro"
nohup ./smart_pomodoro "$MINUTES" > /dev/null 2>&1 &
```

*Note: Since this is a compiled binary, you can move `smart_pomodoro` anywhere on your system (e.g., `/usr/local/bin`) to run it from any folder.*

---

### 2. Stopwatch Pomodoro

#### Compilation
Compile the Swift source file into a binary executable:
```bash
swiftc -O stopwatch_pomodoro.swift -o stopwatch_pomodoro
```
*(If compiling inside a sandboxed terminal environment, redirect the module cache to prevent permission issues)*:
```bash
swiftc -O stopwatch_pomodoro.swift -module-cache-path ./module_cache -Xcc -fmodules-cache-path=./module_cache -o stopwatch_pomodoro
```

#### Run in Background
To kill any running instances and launch it cleanly in the background (does not require duration arguments):
```bash
pkill -f "stopwatch_pomodoro"
nohup ./stopwatch_pomodoro > /dev/null 2>&1 &
```

*Note: Since this is a compiled binary, you can move `stopwatch_pomodoro` anywhere on your system (e.g., `/usr/local/bin`) to run it from any folder.*

---

### 3. MenuBar Notes

#### Compilation
Compile the Swift source file into a binary executable:
```bash
swiftc -O menubar_notes.swift -o menubar_notes
```
*(If compiling inside a sandboxed terminal environment, redirect the module cache to prevent permission issues)*:
```bash
swiftc -O menubar_notes.swift -module-cache-path ./module_cache -Xcc -fmodules-cache-path=./module_cache -o menubar_notes
```

#### Run in Background
To kill any running instances and launch it cleanly in the background:
```bash
pkill -f "menubar_notes"
nohup ./menubar_notes > /dev/null 2>&1 &
```

*Note: Since this is a compiled binary, you can move `menubar_notes` anywhere on your system (e.g., `/usr/local/bin`) to run it from any folder.*
