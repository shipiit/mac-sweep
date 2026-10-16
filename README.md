<div align="center">

# MacSweep

**One native app to clean, speed up, protect and understand your Mac.**

SwiftUI · macOS 15+ · no third-party dependencies · everything stays on your Mac

[Download the latest .dmg](https://github.com/shipiit/mac-sweep/releases/latest)

</div>

---

## What it does

### 🧹 Clean up
| | |
|---|---|
| **Smart Scan** | One button checks junk, security, speed and apps, then runs the clean-up in a step-by-step "Optimizing your Mac" view with a Stop ring. |
| **Space & Junk** | A treemap of every folder, hidden ones included. Recommendations are split into *Safe to remove* and *Review first*, each with "what is it" and "what happens if deleted". |
| **Large & Hidden Files** | The biggest files and folders, filterable to hidden-only or older than a year. |
| **Duplicates & Archive** | Byte-for-byte duplicate finder (SHA-256, at least one copy always kept), similar photos via on-device Vision, and old projects zipped to an external drive or iCloud, verified before the original is removed. |
| **Mail, Trash, Shredder, Privacy** | Mail attachment copies, every Trash bin, secure delete, and browser history/cookies/caches (passwords and bookmarks are never touched). |

### 🛡 Protect
| | |
|---|---|
| **Malware & Security** | SIP, Gatekeeper, FileVault, Firewall and XProtect status; unsigned, temp-folder and fake-Apple startup items; known adware. A heuristic audit, not a signature antivirus. |
| **Extensions** | Browser extensions per profile with their permissions and risk, removable in the right profile. |

### ⚡ Performance
| | |
|---|---|
| **Processes & Memory** | Activity-Monitor-accurate memory, CPU, a "steadily growing" leak flag, idle apps with optional auto-quit. |
| **Optimization & Maintenance** | A ranked advisor with one-click fixes; flush DNS, rebuild Launch Services, reindex Spotlight and more. |
| **Startup Items** | Login items plus launch agents and daemons, with stop, disable and enable. |

### 🛠 Developer
| | |
|---|---|
| **Developer hub** | Docker storage and prune, Homebrew outdated and cleanup, Node/Python/Ruby versions, Xcode DerivedData and simulators, `node_modules` by project, and dev services (Postgres, Redis…) with start/stop/logs. |
| **Ports** | Every listening port with the project folder and command that started it; open, copy or stop it. |

### 🤖 AI Usage
Claude Code and Codex tokens and API-equivalent cost by model, project and session. It also shows live 5-hour and weekly limits, the service status of both tools, and session names. Updates within seconds of a new message. Real Claude plan limits are an **opt-in**, read-only setting.

### 📈 Insights
**Smart Alerts** (low disk, memory leaks, runaway CPU, overheating, a new login item, a big Trash) as notifications, a **14-day Timeline** of CPU, memory, disk and network with spikes explained, and **What Grew** between two disk scans.

### 🖥 Always there
A two-line menu bar item, a notch HUD that expands on hover (System, Apps, Ports, AI, Clean), and a live Dock icon. Themes, accent colours and a customisable dashboard.

---

## Install

1. Download **MacSweep.dmg** from [Releases](https://github.com/shipiit/mac-sweep/releases/latest) and drag MacSweep to Applications.
2. The build is ad-hoc signed (not notarised), so the first time **right-click → Open**, or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/MacSweep.app
   ```
3. For full results, grant **Full Disk Access** in System Settings → Privacy & Security.

## Safety first

- **Allowlist only.** Cleanup comes from an explicit catalog; nothing outside it is ever suggested.
- **PathGuard** refuses anything outside your home folder, `/Applications` and `/Users/Shared`. It also refuses keys (`.ssh`, `.aws`, Keychains), system preferences and MacSweep itself.
- **In-use check.** Anything a running app or dev server uses is skipped automatically.
- **Trash by default.** Permanent deletion is always opt-in and confirmed.
- **Private.** No analytics. The only network calls are ones you trigger, plus the public Claude/OpenAI status pages.

## Build from source

```sh
make test      # 460+ unit tests
make app       # build/MacSweep.app (ad-hoc signed)
make dmg       # build/MacSweep.dmg
make install   # copy to /Applications
```

Requires Xcode 16 / Swift 6 toolchain on macOS 15 or later.
