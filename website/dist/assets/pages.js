import { companionShowcase } from "./companion.js";
import { features } from "./feature-page.js";
import { icon } from "./icons.js";
import { REPO, RELEASES } from "./config.js";
import { cta, sectionHead, shieldArt } from "./components.js";
import { demo, panels } from "./demo.js";
const capabilityCards = [
  [
    "disk",
    "Room for what’s next.",
    "Find junk, large files, duplicate copies, and forgotten projects. Understand every recommendation before you clean.",
    "features.html#cleanup",
    '<div class="storage-bars">' +
      [32, 50, 39, 75, 60, 95, 72, 50, 69, 38, 54, 27]
        .map((h) => `<i style="--h:${h}%"></i>`)
        .join("") +
      "</div>",
  ],
  [
    "shield",
    "Know what needs attention.",
    "Audit security, check finished downloads, inspect app permissions, and see which apps are connecting online.",
    "features.html#protection",
    '<div class="check-lines"><span>Gatekeeper <b>Enabled ✓</b></span><span>FileVault <b>Encrypted ✓</b></span><span>Download checks <b>Watching ✓</b></span></div>',
  ],
  [
    "pulse",
    "Keep your flow going.",
    "See CPU and memory pressure, spot growing processes, manage startup items, and take informed action.",
    "features.html#performance",
    '<svg viewBox="0 0 280 55" width="100%" height="55" aria-hidden="true"><path d="M0 35h25l10-7 10 12 10-29 12 39 10-19h40l10-8 10 16 10-29 10 35 10-15h43l10-12 10 18 10-8h25" stroke="#8da7ff" stroke-width="1.5" fill="none"/></svg>',
  ],
  [
    "code",
    "Built for the builders.",
    "Tame Docker, Homebrew, runtimes, Xcode storage, local services, and ports. Bring order to your dev machine.",
    "developers.html",
    '<div class="mini-code"><span>~/projects</span> → listening on :3000<br><span>✓</span> Every port has a story.</div>',
  ],
  [
    "ai",
    "See your AI footprint.",
    "Track Claude Code and Codex usage by model, project, and session, with API-equivalent cost estimates.",
    "developers.html#ai",
    '<div class="check-lines"><span>Claude Code <b>By project & session</b></span><span>Codex <b>Tokens & estimates</b></span><span>Limits <b>5-hour & weekly</b></span></div>',
  ],
  [
    "chart",
    "Understand what changed.",
    "Smart alerts, a 14-day timeline, and disk scan comparisons turn system activity into useful context.",
    "features.html#insights",
    '<div class="storage-bars">' +
      [20, 25, 35, 26, 55, 47, 40, 75, 62, 90, 60, 55, 40, 58, 30, 25]
        .map((h) => `<i style="--h:${h}%"></i>`)
        .join("") +
      "</div>",
  ],
];
const home = `<section class="hero"><div class="starfield" aria-hidden="true"></div><div class="container hero-grid"><div class="hero-copy"><div class="eyebrow">Your Mac. In its element.</div><h1>A clearer Mac.<br><span>A better flow.</span></h1><p>Clean up the clutter. Understand the activity.<br>Take control of your Mac with one thoughtfully powerful, native app.</p><div class="actions"><a href="download.html" class="btn primary">Get MacSweep ${icon("download")}</a><a href="#explore" class="btn">Explore the app <span aria-hidden="true">↓</span></a></div><div class="micro">Built for macOS 15+ · Apple Silicon</div><div class="hero-note"><span>On-device by design</span><span>Built in Swift</span><span>Native SwiftUI</span></div></div><div class="orb-stage" aria-label="Animated MacSweep system illustration" role="img"><div class="orb-glow"></div><div class="orbit"></div><div class="orbit two"></div><div class="orb"></div><div class="orb-core"><svg viewBox="0 0 120 120" fill="none" aria-hidden="true"><circle cx="60" cy="60" r="42" stroke="#b7cbff" stroke-opacity=".16" stroke-width="7"/><path d="M60 18a42 42 0 1 1-42 42" stroke="#d5e2ff" stroke-width="7" stroke-linecap="round"/><path d="m60 37 6.5 16.5L83 60l-16.5 6.5L60 83l-6.5-16.5L37 60l16.5-6.5Z" fill="#dce8ff"/></svg></div><div class="float-label first"><span class="symbol">✧</span><div><b>A little more breathing room.</b><small>Cleanup with context</small></div></div><div class="float-label second">${icon("shield")}<div><b>Built around your privacy.</b><small>Your data stays on your Mac</small></div></div><div class="float-label third"><span class="status-dot"></span>100% native</div><div class="orb-caption">Clarity, from the inside out.</div></div></div></section><div class="ribbon"><div class="container"><span class="ribbon-label">Thoughtfully built.<br>Deeply capable.</span><span><b>SwiftUI</b>Native from the first click</span><span><b>On-device</b>Your files stay yours</span><span><b>Zero dependencies</b>Built on macOS APIs</span><span><b>Pure Swift core</b>Made for macOS</span></div></div><section class="section container" id="explore">${sectionHead("Meet your Mac, again", "Everything happening.<br>One place to understand it.", "A cleaner desktop is only the beginning. Explore the tools that bring your whole system into focus.")}${demo}</section><section class="section container" style="padding-top:0">${sectionHead("Beyond a cleaner", "A little less chaos.<br>A lot more capability.", "From forgotten caches to the port you can’t find. MacSweep connects the details that matter.")}<div class="grid">${capabilityCards.map(([i, t, p, l, v], n) => `<article class="card reveal"><div class="card-icon">${icon(i)}</div><span class="feature-number">0${n + 1}</span><h3>${t}</h3><p>${p}</p><div class="mini-viz" aria-hidden="true">${v}</div><a class="text-link" href="${l}">Explore ${["cleanup", "protection", "performance", "developer tools", "AI usage", "insights"][n]} →</a></article>`).join("")}</div></section><section class="band"><div class="container section split"><div class="reveal"><div class="eyebrow">Power with a little restraint</div><h2>Your files deserve<br>a thoughtful approach.</h2><p>Cleanup should come with explanations. MacSweep separates safe recommendations from items that need a closer look, protects sensitive paths, and uses the Trash by default.</p><a class="text-link" href="trust.html">How MacSweep protects your files →</a></div>${shieldArt}</div></section><section class="container section split"><div class="terminal reveal"><div class="demo-top"><div class="traffic" aria-hidden="true"><i></i><i></i><i></i></div>Under the hood</div><div class="terminal-body"><div class="comment">// Built for the system it runs on.</div><br><div><span class="prompt">interface</span> &nbsp;SwiftUI</div><div><span class="prompt">logic</span> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MacSweepCore</div><div><span class="prompt">foundation</span> macOS APIs</div><div><span class="prompt">dependencies</span> 0</div><br><div class="comment">// fts · libproc · Security · FSEvents</div><div class="output">Native tools. A clearer picture.<span class="cursor"> ▌</span></div></div></div><div class="reveal"><div class="eyebrow">Built around native foundations</div><h2>Made for macOS.<br>Built around native APIs.</h2><p>A SwiftUI interface backed by a pure Swift core. Explore the documented safeguards and understand how the tools work together.</p><a class="text-link" href="trust.html">Read about safeguards →</a></div></section>${companionShowcase}${cta}`;
const devFeatures = [
  [
    "layers",
    "Docker & Homebrew",
    "See Docker storage and available prune actions. Review outdated Homebrew packages and run cleanup.",
  ],
  [
    "code",
    "Runtimes & Xcode",
    "Inspect Node, Python, and Ruby versions. Find Xcode DerivedData and simulator storage.",
  ],
  [
    "disk",
    "Every node_modules",
    "Discover dependency folders across your home directory and decide what you can rebuild.",
  ],
  [
    "terminal",
    "Services & ports",
    "Manage local services such as Postgres and Redis. Trace listening ports to the command and project that started them.",
  ],
];
const developers = `<section class="subhero"><div class="container"><div class="eyebrow">For the people who build</div><h1>Your machine is a workspace.<br><span class="gradient-text">Give it a control room.</span></h1><p>The local server you forgot. The cache that grew. The AI session you want to understand. Bring your development environment into view.</p><div class="actions"><a class="btn primary" href="download.html">Get MacSweep ${icon("download")}</a><a class="btn" href="#ai">Explore AI usage ↓</a></div></div></section><section class="container section split"><div class="reveal"><div class="eyebrow">A port is just the beginning</div><h2>Know what’s running.<br>And where it came from.</h2><p>See every listening port alongside the project folder and command that started it. Open the address, copy it, or stop the process from one place.</p><ul class="checklist"><li>Connect a process to a project</li><li>Start and stop supported local services</li><li>Inspect service logs without losing context</li></ul></div><div class="terminal reveal"><div class="demo-top"><div class="traffic" aria-hidden="true"><i></i><i></i><i></i></div>Developer workspace · illustration</div><div class="terminal-body"><span class="comment">// Every port, accounted for.</span><br><br><div class="terminal-row"><span>:3000 &nbsp; node</span><span class="prompt">LISTENING</span></div><div class="comment">~/projects/studio → npm run dev</div><br><div class="terminal-row"><span>:5432 &nbsp; postgres</span><span class="prompt">RUNNING</span></div><div class="comment">Local database</div><br><div class="terminal-row"><span>:6379 &nbsp; redis-server</span><span class="prompt">RUNNING</span></div><div class="comment">Local cache</div><br><div class="output"><span class="prompt">↳</span> Less detective work. More building.</div></div></div></section><section class="container section" style="padding-top:0">${sectionHead("Less buildup, more building", "The tools behind your tools.")}<div class="two-grid">${devFeatures.map(([i, t, p]) => `<article class="card reveal"><div class="card-icon">${icon(i)}</div><h3>${t}</h3><p>${p}</p></article>`).join("")}</div></section><section class="band" id="ai"><div class="container section split"><div class="reveal"><div class="eyebrow">AI usage, with context</div><h2>Your sessions add up.<br>Now you can see how.</h2><p>Explore Claude Code and Codex tokens and API-equivalent costs by model, project, and session. Keep an eye on 5-hour and weekly limits alongside provider service status.</p><ul class="checklist"><li>Local session indexing with updates within seconds</li><li>Project, session, and model breakdowns</li><li>Optional, read-only Claude plan limits</li></ul><div class="notice">API-equivalent costs are estimates, not subscription bills. Real Claude plan usage requires an explicit opt-in. Public provider status checks use the network.</div></div><div class="demo-shell reveal"><div class="demo-top">AI Usage · sample data</div><div class="demo-panel">${panels.ai}</div></div></div></section><section class="container section split"><div class="terminal reveal"><div class="demo-top">Build it yourself</div><div class="terminal-body"><div class="comment"># Xcode 16 / Swift 6 · macOS 15+</div><br><span class="prompt">$</span> git clone https://github.com/shipiit/mac-sweep.git<br><span class="prompt">$</span> cd mac-sweep<br><span class="prompt">$</span> make test<br><span class="prompt">$</span> make app<br><span class="prompt">$</span> make dmg</div></div><div class="reveal"><div class="eyebrow">Readable by design</div><h2>Native all the way down.</h2><p>MacSweepCore holds the pure Swift logic. The app stays focused on SwiftUI views and observable models. No third-party dependencies; macOS APIs do the work.</p><a class="text-link" href="${REPO}">Explore the architecture ↗</a></div></section>${cta}`;
const trust = `<section class="subhero"><div class="container"><div class="eyebrow">Trust is in the details</div><h1>Powerful tools.<br><span class="gradient-text">Thoughtful boundaries.</span></h1><p>Your Mac holds your work, your ideas, and your everyday life. Understand what MacSweep checks, what it protects, and how you stay in control.</p></div></section><section class="container section split"><div class="reveal"><div class="eyebrow">Private by design</div><h2>At home on your Mac.<br>Your data stays there.</h2><p>Disk analysis, duplicate matching, and system inspection happen on your device. Similar-photo matching uses Apple’s on-device Vision framework. MacSweep has no analytics.</p><p>Network requests cover actions you trigger and public Claude and OpenAI status pages. Real Claude plan-limit access is optional and read-only.</p></div>${shieldArt}</section><section class="band"><div class="container section">${sectionHead("Cleanup safeguards", "A considered path<br>from scan to Trash.", "The cleanup engine uses several checks before anything is eligible for removal.")}<div class="flow reveal"><div><small>01 / CATALOG</small><h3>Allowlisted cleanup.</h3><p>Automatic cleanup recommendations come from a defined catalog.</p></div><div><small>02 / PATHGUARD</small><h3>Protected paths.</h3><p>Sensitive credentials, keychains, macOS preferences, and standard roots are refused.</p></div><div><small>03 / IN-USE CHECK</small><h3>Respect active work.</h3><p>Items detected in use by running apps or development servers are skipped.</p></div><div><small>04 / CONFIRM</small><h3>Trash by default.</h3><p>Review and confirm. Permanent deletion is a separate, explicit choice.</p></div></div><div class="notice">PathGuard limits removal to eligible descendants of your home folder, /Applications, and /Users/Shared, while refusing protected roots and subtrees. Duplicate cleanup keeps at least one copy. Archives must be verified before originals can be removed.</div></div></section><section class="container section split"><div class="reveal"><div class="eyebrow">Understand protection</div><h2>See the signals.<br>Know the limits.</h2><p>MacSweep checks for disguised apps, invalid or missing signatures, Gatekeeper rejections, known adware, and hidden executables. It works alongside Apple’s built-in XProtect.</p><div class="notice"><strong>Clear scope:</strong> MacSweep is a heuristic checker, not a signature antivirus. It checks files after downloads finish. It does not provide Apple Endpoint Security real-time execution blocking.</div></div><div class="numbered reveal"><div class="step"><div><h3>A download finishes.</h3><p>The file is checked after it has finished downloading.</p></div></div><div class="step"><div><h3>Signals are assessed.</h3><p>Signatures, disguises, Gatekeeper results, and threat rules inform the finding.</p></div></div><div class="step"><div><h3>You get a clear next step.</h3><p>Clear threats are quarantined; suspicious items raise a notification. Quarantined files lose execute permission and can be restored or deleted.</p></div></div></div></section><section class="container section" style="padding-top:0">${sectionHead("No hidden story", "Inspect it for yourself.")}<div class="two-grid"><article class="card reveal"><div class="card-icon">${icon("code")}</div><h3>Clear implementation boundaries.</h3><p>The app has a Swift core for cleanup, path safeguards, threat rules, and tests. The app repository is private; source access is limited to authorized collaborators.</p><a class="text-link" href="${REPO}">App repository (access required) ↗</a></article><article class="card reveal"><div class="card-icon">${icon("lock")}</div><h3>Installation, explained.</h3><p>The current build is ad-hoc signed and not notarised. Full Disk Access enables more complete scan results.</p><a class="text-link" href="download.html#installation">Read the setup guide →</a></article></div></section>${cta}`;
const faqs = [
  [
    "Which Macs are supported?",
    "MacSweep targets macOS 15 or later on Apple Silicon. Building from source requires the Xcode 16 / Swift 6 toolchain.",
  ],
  [
    "Why does macOS show a first-launch warning?",
    "The release build is ad-hoc signed and not notarised. The project README recommends right-clicking the app and choosing Open for first launch. Follow the guidance shown by macOS for your version; only open a download whose source you trust.",
  ],
  [
    "Why does it ask for Full Disk Access?",
    "macOS restricts access to certain folders. Full Disk Access lets MacSweep show more complete scan results. Enable it in System Settings → Privacy & Security → Full Disk Access.",
  ],
  [
    "Will it delete files automatically?",
    "Standard cleanup asks for confirmation and uses the Trash by default. Permanent deletion is opt-in and confirmed. Download Protection can automatically quarantine files judged to be clear threats after they finish downloading.",
  ],
  [
    "Is it a replacement for antivirus?",
    "MacSweep uses heuristic checks and works alongside Apple XProtect. It is not a signature antivirus and does not offer Endpoint Security real-time execution blocking.",
  ],
  [
    "Are AI cost figures my actual bill?",
    "No. API-equivalent costs estimate token usage at API rates. They do not represent a Claude or ChatGPT subscription bill. Real Claude plan-limit access is an optional, read-only setting.",
  ],
  [
    "Can I build it from source?",
    'Authorized collaborators can clone the private <a href="https://github.com/shipiit/mac-sweep">app repository</a>, then run make test and make app. Run make dmg to package a disk image. The public website repository contains only this showcase.',
  ],
];
const download = `<section class="download-hero"><div class="container"><img class="download-icon" src="assets/icon.svg" alt="MacSweep app icon" width="98" height="98"><div class="eyebrow">A fresh perspective for your Mac</div><h1>Make room for<br><span class="gradient-text">your next idea.</span></h1><p>One native app to clean, speed up, protect, and understand your Mac.</p><div class="actions"><a href="${RELEASES}" class="btn primary">GitHub releases (access required) ${icon("download")}</a><a href="features.html" class="btn">Explore capabilities →</a></div><div class="micro">macOS 15+ · Apple Silicon · Ad-hoc signed, not notarised</div></div></section><section class="container section split" id="installation"><div class="reveal"><div class="eyebrow">Get up and running</div><h2>A few steps.<br>A clearer Mac.</h2><p>Download the disk image from the project’s GitHub releases. Here’s what to expect the first time you open MacSweep.</p><div class="notice">The Mac app repository is private. Release downloads require repository access; the public website does not grant access to the app or publish its source.</div></div><div class="numbered reveal"><div class="step"><div><h3>Download and install.</h3><p>Open MacSweep.dmg and drag MacSweep into Applications.</p></div></div><div class="step"><div><h3>Open for the first time.</h3><p>The build is not notarised. Right-click MacSweep in Applications and choose Open, following the macOS prompts.</p></div></div><div class="step"><div><h3>Allow a fuller picture.</h3><p>For complete results, enable Full Disk Access in System Settings → Privacy & Security.</p></div></div></div></section><section class="band"><div class="container section">${sectionHead("Good questions", "A little clarity before you start.")}<div class="faq">${faqs.map(([q, a]) => `<details><summary>${q}</summary><p>${a}</p></details>`).join("")}</div></div></section><section class="cta"><h2>Curious about the details?</h2><p>Explore every capability or visit the public website repository.</p><div class="actions"><a class="btn primary" href="features.html">Explore all capabilities ${icon("arrow")}</a><a class="btn" href="https://github.com/shipiit/mac-sweep-website">Website on GitHub ↗</a></div></section>`;
const pages = { index: home, features, developers, trust, download };

export { pages };
