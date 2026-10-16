# MacSweep

A native macOS app (SwiftUI, no third-party dependencies) to see and control everything on your Mac:

- **Storage**: a treemap of every folder, hidden ones included, coloured by category. Allowlisted cleanup recommendations are split into *Safe to remove* and *Review first*, and a "What is it?" explanation is shown for folders and files.
- **Large & Hidden Files**: the biggest files and folders, filterable to hidden-only or older than a year.
- **Processes & Memory**: footprint memory (matches Activity Monitor), CPU, threads, per-process memory history, a "steadily growing" flag for possible leaks, and quit / force kill with an admin fallback.
- **Ports**: every listening TCP/UDP port with its owner process, executable, working directory and command line. Shows whether the port is exposed to the network, opens it in the browser, and kills the owner.
- **Startup Items**: LaunchAgents and LaunchDaemons with their loaded/running state, plus stop, disable and enable.
- **Smart Scan**: one button that checks junk, security, speed and apps, with a live checklist and results.
- **Privacy**: browser history, cookies, sessions and caches for Chrome, Brave, Edge, Arc, Firefox and Safari, plus Recent Items. Passwords, autofill and bookmarks are never touched.
- **Malware & Security**: SIP, Gatekeeper, FileVault, Firewall and XProtect status; unsigned, temp-folder and fake-Apple startup items; known adware; high-access browser extensions. Bad startup items can be removed (unloaded, then moved to the Trash). This is a heuristic audit, not a signature antivirus.
- **Extensions**: Quick Look, Spotlight, preference panes, plug-ins and services.
- **Optimization**: a ranked advisor (disk, memory pressure, swap, runaway processes, login items, battery health, uptime) with one-click fixes.
- **Maintenance**: flush DNS, rebuild Launch Services, reindex Spotlight, thin Time Machine snapshots, verify disk, clear font caches.
- **Uninstaller**: apps with size and last used date, removed together with their leftovers; also finds leftovers of apps you already deleted.
- **Updater**: macOS updates and outdated Homebrew apps and tools.
- **Saved & scheduled scans**: the last scan loads instantly; an automatic rescan runs nightly, every morning or every 6 hours, at background priority (skipped on low battery).
- **Menu bar & notch**: live CPU and memory in the menu bar. A small pill sits around the notch and expands on hover into a dashboard.

## Safety

- Cleanup uses an explicit allowlist (`CleanupCatalog`). Nothing is pre-selected.
- `PathGuard` refuses anything outside home, `/Applications` and `/Users/Shared`. It also refuses standard folders, keys (`.ssh`, `.aws`, Keychains), preferences and MacSweep itself.
- Before cleaning, `InUseDetector` warns about and skips locations that a running process executes from or works in, and caches of apps that are open.
- Items go to the Trash by default. "Delete immediately" is opt-in.
- Critical processes (`launchd`, `WindowServer`, `loginwindow`, …) can't be killed.

## Build

```sh
make test      # 100+ unit tests for the core engine
make app       # build/MacSweep.app (ad-hoc signed)
make install   # copy to /Applications (keeps the Full Disk Access grant stable)
```

Grant **Full Disk Access** (System Settings → Privacy & Security) to see Mail, Messages, Safari and app containers.
