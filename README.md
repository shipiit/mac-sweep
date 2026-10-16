<div align="center">

# MacSweep

**One native app to clean, speed up, protect and understand your Mac.**

SwiftUI · macOS 15+ · Apple Silicon · no third-party dependencies · everything stays on your Mac

[**⬇ Download the latest .dmg**](https://github.com/shipiit/mac-sweep/releases/latest)

![Version](https://img.shields.io/github/v/release/shipiit/mac-sweep?label=version) ![macOS](https://img.shields.io/badge/macOS-15%2B-black) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![Tests](https://img.shields.io/badge/tests-510%2B-brightgreen) ![Dependencies](https://img.shields.io/badge/dependencies-0-blue)

</div>

---

## At a glance

```mermaid
mindmap
  root((MacSweep))
    Clean up
      Smart Scan
      Space & Junk treemap
      Large & Hidden Files
      Duplicates & Archive
      Mail · Trash · Shredder · Privacy
    Protect
      Malware Scan
      Download Protection
      Security Audit
      App Permissions
      Network Monitor
      Sharing & Wi-Fi
      Backups
      Extensions
    Performance
      Processes & Memory
      Optimization
      Maintenance
      Startup Items
    Developer
      Docker · Homebrew
      Runtimes · Xcode
      node_modules
      Services · Ports
    AI Usage
      Claude Code
      Codex
      Limits & status
    Insights
      Smart Alerts
      Timeline
      What Grew
```

## What it does

### 🧹 Clean up
| | |
|---|---|
| **Smart Scan** | One button checks junk, security, speed and apps, then cleans up step by step in an "Optimizing your Mac" view with a Stop ring. |
| **Space & Junk** | A treemap of every folder, hidden ones included. Recommendations are split into *Safe to remove* and *Review first*, each explaining what it is and what happens if deleted. |
| **Large & Hidden Files** | The biggest files and folders, filterable to hidden-only or older than a year. |
| **Duplicates & Archive** | Byte-for-byte duplicates (SHA-256; one copy is always kept), similar photos via on-device Vision, and old projects zipped to an external drive or iCloud, verified before the original can go. |
| **Mail, Trash, Shredder, Privacy** | Mail attachment copies, every Trash bin, secure delete, and browser history, cookies and caches (passwords and bookmarks are never touched). |

### 🛡 Protect
| | |
|---|---|
| **Malware Scan** | Finds disguised programs (`invoice.pdf.app`), broken or missing code signatures, Gatekeeper rejections, known adware and hidden executables. Each finding can be quarantined, revealed or ignored. |
| **Download Protection** | Checks every finished download. Clear threats are moved to quarantine before you can open them; suspicious files raise a notification. On by default. |
| **Quarantine** | Quarantined files have their execute permission removed. Restore or delete them any time. |
| **Security Audit** | SIP, Gatekeeper, FileVault, Firewall and XProtect status, plus suspicious startup items. |
| **App Permissions** | Which apps can use the camera, microphone, screen recording, Full Disk Access or Accessibility, flagged by risk, with a jump to revoke. |
| **Network Monitor** | Live connections per app with the hosts they talk to; untrusted programs going online are flagged. |
| **Sharing & Wi-Fi · Backups · Extensions** | Wi-Fi security, SSH and screen sharing, firewall and AirDrop; Time Machine age and excluded folders; browser extensions per profile with their permissions. |

### ⚡ Performance
| | |
|---|---|
| **Processes & Memory** | Activity-Monitor-accurate memory and CPU, a leak flag for steadily growing apps, idle apps with optional auto-quit. |
| **Optimization & Maintenance** | A ranked advisor with one-click fixes; flush DNS, rebuild Launch Services, reindex Spotlight and more. |
| **Startup Items** | Login items, launch agents and daemons, with stop, disable and enable. |

### 🛠 Developer
| | |
|---|---|
| **Developer hub** | Docker storage and prune, Homebrew outdated packages and cleanup, Node/Python/Ruby versions, Xcode DerivedData and simulators, every `node_modules` in your home folder, and dev services (Postgres, Redis…) with start, stop and logs. |
| **Ports** | Every listening port with the project folder and command that started it; open, copy or stop it. |

### 🤖 AI Usage
Claude Code and Codex tokens and API-equivalent cost by model, project and session. It shows live 5-hour and weekly limits and the service status of both tools, and updates within seconds of each message. Real Claude plan limits are an **opt-in**, read-only setting.

### 📈 Insights
**Smart Alerts** notify you about low disk, memory leaks, runaway CPU, overheating, new login items and a big Trash. A **14-day Timeline** shows CPU, memory, disk and network, with spikes explained. **What Grew** compares two disk scans.

### 🖥 Always there
A two-line menu bar item, a notch HUD that expands on hover (System, Apps, Ports, AI, Clean), a live Dock icon, themes and accent colours. The sidebar folds, and any page can be hidden in Settings → Sidebar.

---

## How protection works

```mermaid
flowchart LR
    D[New file in Downloads] --> W{Finished<br/>downloading?}
    W -- no --> D
    W -- yes --> C[Check it]
    C --> R1[Disguised as a document?]
    C --> R2[Signature broken or missing?]
    C --> R3[Gatekeeper rejects it?]
    C --> R4[Known adware or hidden program?]
    R1 & R2 & R3 & R4 --> V{Verdict}
    V -- clear threat --> Q[🔒 Quarantine<br/>execute bit removed]
    V -- suspicious --> N[🔔 Notification]
    V -- clean --> OK[✓ Nothing to do]
    Q --> U[Restore or delete<br/>from the Quarantine tab]
```

MacSweep works alongside Apple's built-in XProtect; it is a heuristic checker, not a signature antivirus. macOS reserves true real-time blocking for apps with Apple's Endpoint Security entitlement, so files are quarantined the moment they finish downloading.

## How cleanup stays safe

```mermaid
flowchart TD
    S[Scan] --> A[Allowlisted catalog only]
    A --> P{PathGuard}
    P -- outside home, Applications,<br/>keys, preferences, MacSweep --> X[Refused]
    P -- allowed --> I{In use by a running<br/>app or dev server?}
    I -- yes --> K[Skipped]
    I -- no --> T[Moved to the Trash<br/>after you confirm]
```

- **Allowlist only:** nothing outside the cleanup catalog is ever suggested.
- **PathGuard** refuses anything outside your home folder, `/Applications` and `/Users/Shared`, plus keys (`.ssh`, `.aws`, Keychains), system preferences and MacSweep itself.
- **Trash by default:** permanent deletion is always opt-in and confirmed. Duplicate removal always keeps one copy; archives are verified before the original can go.
- **Private:** no analytics. The only network calls are ones you trigger, plus the public Claude and OpenAI status pages.

## Architecture

```mermaid
flowchart LR
    subgraph App["MacSweep (SwiftUI app)"]
        V[Pages & views] --> M["@Observable models"]
        MB[Menu bar · Notch · Dock] --> M
    end
    subgraph Core["MacSweepCore (pure Swift, unit-tested)"]
        DS[Disk scanner & cleanup]
        TH[Threat rules & quarantine]
        AI[AI usage index]
        DV[Developer tools]
        SY[System, process, network readers]
    end
    M --> Core
    Core --> OS[(macOS APIs<br/>fts · libproc · Security · FSEvents)]
```

All logic lives in `MacSweepCore` with 510+ tests; the app target is thin views and models.

## Install

1. Download **MacSweep.dmg** from [Releases](https://github.com/shipiit/mac-sweep/releases/latest) and drag MacSweep to Applications.
2. The build is ad-hoc signed (not notarised), so the first time **right-click → Open**, or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/MacSweep.app
   ```
3. For full results, grant **Full Disk Access** in System Settings → Privacy & Security.

## Build from source

```sh
make test      # 510+ unit tests
make app       # build/MacSweep.app (ad-hoc signed)
make dmg       # build/MacSweep.dmg
make install   # build and copy to /Applications
```

Requires Xcode 16 / Swift 6 toolchain on macOS 15 or later.
