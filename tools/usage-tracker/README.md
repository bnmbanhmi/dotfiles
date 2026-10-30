# Usage Tracker (macOS Menu Bar)

Minimalist, monochrome personal AI subscription and usage tracker for the macOS menu bar.

Designed to be lightweight, text-only (no emojis, no bloated dashboards), and integrated directly into the `dotfiles` ecosystem.

---

## Design Principles

1. **Text-Only, Monochrome Aesthetics & Granular Hierarchy:**
   - Menu bar title uses a clear, structured hierarchy: `[acc]-[platform]-[model]-[type]`
     - `0-AGY-Gemini-5h: 53%` (Account 0, Antigravity, Gemini pool, 5-hour limit)
     - `0-AGY-Gemini-Weekly: 53%` (Account 0, Antigravity, Gemini pool, weekly limit)
     - `0-AGY-Claude-Weekly: 31%` (Account 0, Antigravity, Claude/GPT pool, weekly limit)
     - `0-Gemini-Weekly: 17%` (Account 0, Gemini Web, weekly limit)
     - `1-Gemini-Weekly: 11%` (Account 1, Gemini Web, weekly limit)
     - `OpenCode-Today: $0.00`
   - Zero colorful emojis, no `[]` brackets, or noisy widgets.
2. **Auto-Harvesting Multi-Account:**
   - **Antigravity:** Automatically registers the active account (`~/.gemini/antigravity_accounts.json`). When switching accounts in Antigravity IDE, newly detected accounts are automatically harvested and preserved so all accounts are monitored concurrently without re-logging in.
   - **Gemini Web:** Maps directly to Account 0 and Account 1 from Google Chrome (`/usage` and `/u/1/usage`).
   - The dropdown groups metrics cleanly under native subtle headers:
     ```text
     0 - Antigravity (Gemini)
       ✓ Weekly: 53.3% (23h 45m)
         5h: 52.8% (1h 36m)
     0 - Antigravity (Claude/GPT)
         Weekly: 31.0% (4d 6h)
         5h: 0.0% (4h 59m)
     0 - Gemini Web
         Weekly: 17% (3 Nov at 19:44)
         5h: 20% (13:44)
     1 - Gemini Web
         Weekly: 11% (Nov 2 at 2:27 PM)
         5h: 0% (2:27 PM)
     ChatGPT (Free)
         Primary: 0% (30d 0h)
     OpenCode
         Today: $0.00 (0 tok)
         Week: $0.00 (0 tok)
         All-Time: 8.6M tok
     ```
   - Clicking any item in the dropdown instantly switches it to be the active metric on the Menu Bar.
3. **Decoupled Architecture:**
   - **Backend (`fetcher.py`):** Runs periodically in the background to collect metrics from local databases, OAuth endpoints, or browser cookies, and caches the result to `stats.json`.
   - **Frontend (`usage_tracker.swift`):** A lightweight native Swift menu bar binary that simply reads `stats.json`, renders the menu bar item, and lets the user pick the active provider.

---

## Supported Providers & Data Sources

| Provider Tag | Metrics Tracked | Data Source & Mechanism |
| :--- | :--- | :--- |
| **AGY** *(Antigravity - Gemini)* | 5-Hour & Weekly quota remaining (%) | Google Cloud Code API via local `~/.gemini/jetski-standalone-oauth-token` (Bucket: `gemini-5h`, `gemini-weekly`) |
| **AGY-Claude** *(Antigravity - 3rd Party)* | 5-Hour & Weekly Claude / GPT quota (%) | Google Cloud Code API (Bucket: `3p-5h`, `3p-weekly`) |
| **AGY-Argon** *(Antigravity - Argon)* | Weekly Argon quota (%) | Google Cloud Code API (Group: `Gemini 4 Argon`) |
| **OpenCode** | Today & Weekly Cost ($) and Token counts | Local SQLite database at `~/.local/share/opencode/opencode.db` (100% offline query on `session` table) |
| **Gemini-0** *(Gemini Web - Account 0)* | Daily & Weekly prompts / usage tier | `https://gemini.google.com/usage` |
| **Gemini-1** *(Gemini Web - Account 1)* | Daily & Weekly prompts / usage tier | `https://gemini.google.com/u/1/usage` |
| **ChatGPT** | Daily session / message limits & reset timers | OpenAI backend endpoint (`chatgpt.com/backend-api/wham/usage`) or API |

---

## File Structure

```text
tools/usage-tracker/
├── README.md               # Project spec, tracking progress, and documentation
├── fetcher.py              # Background metric scraper and normalizer
├── usage_tracker.swift     # Minimalist native Swift Menu Bar application
├── stats.json              # Local cache storing normalized metrics & active selection
└── Makefile / build script # Compilation helper for swiftc
```

---

## Implementation Progress

- [x] **Research & Proof of Concept:**
  - [x] Analyzed `openusage` architecture (`/tmp/openusage`).
  - [x] Verified Antigravity quota retrieval via `cloudcode-pa.googleapis.com` (Gemini: 47% weekly used, Claude: 31% weekly used).
  - [x] Verified OpenCode offline SQLite schema (`~/.local/share/opencode/opencode.db`).
- [x] **Project Blueprint & Spec:**
  - [x] Created `README.md` defining data sources, styling rules, and decoupled architecture.
- [x] **Phase 1: Fetcher Engine (`fetcher.py`):**
  - [x] Implement Antigravity module (Gemini, Claude/GPT, Argon).
  - [x] Implement OpenCode module (Today/Week cost and tokens via SQLite).
  - [x] Output structured `stats.json`.
- [x] **Phase 2: Minimalist Menu Bar App (`usage_tracker.swift`):**
  - [x] Implement `NSStatusItem` displaying active provider text (`AGY: 47%`).
  - [x] Implement `NSMenu` dropdown with checkmark toggle to switch active provider.
  - [x] Persist active provider selection across restarts.
  - [x] "Refresh" trigger to invoke `fetcher.py`.
- [x] **Phase 3: Web Providers (Gemini Web & ChatGPT):**
  - [x] Multi-account Gemini Web scraper (`/usage` and `/u/1/usage` via Google Chrome AppleScript without stealing focus).
  - [x] ChatGPT usage integration (`chatgpt.com/backend-api/wham/usage` via Codex credentials in `~/.codex/auth.json` with auto OAuth refresh).
- [x] **Phase 4: Integration with Dotfiles:**
  - [x] Built binary `bin/usage_tracker` and added `--build` flag to `install.sh`.
  - [x] Dynamic menu reload on click (`menuWillOpen`).
