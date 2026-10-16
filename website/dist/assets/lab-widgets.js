import { icon } from "./icons.js";
const title = (name, tag = "Sample data") =>
  `<div class="lab-toolbar"><span>${name}</span><span class="live-tag">${tag}</span></div>`;
const rows = (items) =>
  `<div class="widget-rows">${items.map(([name, value, detail], i) => `<div style="--delay:${i * 100}ms"><span>${name}${detail ? `<small>${detail}</small>` : ""}</span><b>${value}</b></div>`).join("")}</div>`;
const meter = (label, value, width) =>
  `<div class="widget-meter"><span>${label}<b>${value}</b></span><i><em style="--fill:${width}%"></em></i></div>`;
const flow = (items) =>
  `<div class="widget-flow">${items.map((x, i) => `<div style="--step:${i}"><small>0${i + 1}</small><b>${x}</b></div>`).join("")}</div>`;
const fileTable = (names) => rows(names.map(([n, v, c]) => ["▤ " + n, v, c]));

function storage() {
  return (
    title("Explorer · click a folder to go deeper") +
    `<div class="storage-breadcrumb"><button data-disk-back disabled>← Macintosh HD</button><span class="disk-path">/</span></div><div class="deep-treemap"><button data-folder="Developer"><b>Developer</b><strong>32.6 GB</strong><small>Click to explore →</small></button><button data-folder="Downloads"><b>Downloads</b><strong>12.4 GB</strong><small>Click to explore →</small></button><button data-folder="Caches"><b>Caches</b><strong>8.2 GB</strong><small>Click to explore →</small></button></div><div class="widget-cleanup"><label><input type="checkbox" data-clean-example> Select sample rebuildable caches</label><span class="selection-total">Nothing selected</span></div><p class="lab-footnote">Explore sample folders. Selecting a recommendation changes the demo total; it does not delete anything.</p>`
  );
}
function processes() {
  return (
    title("Processes & memory · expand an app") +
    `<div class="memory-stack"><i style="width:38%;background:#5d9df4"></i><i style="width:18%;background:#edaa69"></i><i style="width:28%;background:#b887e7"></i><i style="width:16%;background:#70ccc6"></i></div><div class="lab-legend"><span>App</span><span>Wired</span><span>Compressed</span><span>Cached</span></div><div class="process-details">${[
      ["Browser", "2.8 GB", "42%", "8 processes · 124 threads", 82],
      ["Studio", "1.4 GB", "18%", "4 processes · 67 threads", 48],
      ["Python", "680 MB", "6%", "2 processes · 18 threads", 27],
    ]
      .map(
        ([name, mem, cpu, detail, w]) =>
          `<details><summary><span>› ${name}</span><i><em style="--fill:${w}%"></em></i><b>${mem}</b><small>${cpu}</small></summary><div class="process-expanded"><p>${detail}</p><div><span>Renderer</span><b>${name === "Browser" ? "1.6 GB" : "420 MB"}</b></div><div><span>Background worker</span><b>${name === "Browser" ? "1.2 GB" : "260 MB"}</b></div><p class="lab-footnote">Expand groups to understand their child processes. Sample data.</p></div></details>`,
      )
      .join("")}</div>`
  );
}
function ports() {
  return (
    title("Ports · expand a process for its context") +
    `<div class="port-summary"><span><b>3</b> Listening</span><span><b>2</b> This Mac only</span><span><b>1</b> Network reachable</span></div>${[
      [
        "3000",
        "node",
        "This Mac",
        "~/projects/studio",
        "npm run dev -- --host 127.0.0.1",
      ],
      [
        "5432",
        "postgres",
        "This Mac",
        "/opt/homebrew/var/postgresql",
        "postgres -D ./data",
      ],
      [
        "8080",
        "python",
        "Network",
        "~/projects/demo",
        "python -m http.server 8080 --bind 0.0.0.0",
      ],
    ]
      .map(
        ([port, name, access, path, cmd]) =>
          `<details class="port-detail"><summary><strong>:${port}</strong><span>${name}<small>${access}</small></span><b>Details ＋</b></summary><div class="port-expanded"><span>PROJECT FOLDER</span><code>${path}</code><span>STARTING COMMAND</span><code>${cmd}</code><p>${access === "This Mac" ? "Loopback: connections are bound to this computer." : "Bound to all interfaces: potentially reachable from the network, subject to routing and firewall rules."}</p><button class="widget-action" data-copy-port="${port}">Copy example address</button><small class="port-copy-status" role="status"></small></div></details>`,
      )
      .join("")}`
  );
}
function limits() {
  return (
    title("AI limits · recorded sample windows") +
    `<div class="limits-provider"><b>Claude Code</b><span>Opt-in real plan data</span>${meter("Session (5h)", "32% left", 32)}${meter("Weekly", "48% left", 48)}</div><div class="limits-provider"><b>Codex</b><span>Recorded usage data</span>${meter("Session (5h)", "87% left", 87)}${meter("Weekly", "81% left", 81)}</div><p class="lab-footnote">Without Claude plan access, the app shows transcript-derived block timing. Time left is not the same as quota left.</p>`
  );
}
function cost() {
  return (
    title("Cost by model · API-equivalent estimate") +
    `<div class="cost-illustration"><div class="cost-donut"><span><b>$8.62</b><small>API value</small></span></div><div>${rows(
      [
        ["Model A", "$6.14", "1.6M tokens"],
        ["Model B", "$2.48", "0.8M tokens"],
      ],
    )}</div></div><div class="cost-stats"><span>Avg / active day<b>$1.23</b></span><span>Requests<b>148</b></span><span>Cache hits<b>82%</b></span></div><p class="lab-footnote">Illustrative models and rates. This is not an invoice or subscription charge. Actual models without known pricing are identified as unpriced.</p>`
  );
}
const settingRows = {
  0: [
    ["Launch at login", "Optional"],
    ["Automatic scan", "Every night · 2 AM"],
    ["Menu bar style", "CPU & memory"],
    ["Notch HUD", "On"],
    ["Live Dock icon", "On"],
  ],
  2: [
    ["Activity chart", "Shown"],
    ["Storage & Memory", "Shown"],
    ["Battery & Network", "Shown"],
    ["Listening ports", "Shown"],
    ["Connected devices", "Optional"],
  ],
  3: [
    ["Smart Scan", "Always shown"],
    ["Dashboard", "Always shown"],
    ["Developer", "Show / hide"],
    ["Protection", "Show / hide"],
    ["Insights", "Show / hide"],
  ],
  4: [
    ["Show limits for", "Claude Code / Codex"],
    ["Real Claude plan limits", "Off by default"],
    ["Keychain access", "Requires permission"],
    ["Usage access", "Read-only"],
  ],
  5: [
    ["Track app time", "Optional"],
    ["Local history retention", "30 days"],
    ["Clear usage history", "Confirmation required"],
    ["Data location", "Application Support"],
  ],
  6: [
    ["Jump to section", "⌘1–⌘9"],
    ["Refresh current page", "⌘R"],
    ["Up one disk folder", "⌘↑"],
    ["Search list", "⌘F"],
    ["Settings", "⌘,"],
    ["Quit MacSweep", "⌘Q"],
  ],
};

export function widgetVisual(group, index) {
  const id = group.id;
  if (id === "cleanup") {
    switch (index) {
      case 0:
        return (
          title("Smart Scan · a guided sequence", "Animated illustration") +
          `<div class="scan-cinema"><div class="cinema-ring"><strong>Scan</strong></div><div class="scan-cinema-steps">${["Space & junk", "Security checks", "Performance", "Applications"].map((s, i) => `<span style="--step:${i}"><b>0${i + 1}</b>${s}<small>Inspect</small></span>`).join("")}</div></div><p class="lab-footnote">The Mac app shows progress and a Stop control. Try the start/stop demo on the Overview page.</p>`
        );
      case 1:
        return storage();
      case 2:
        return (
          title("Large & hidden files · sample inventory") +
          fileTable([
            [
              "project-archive.zip",
              "4.8 GB",
              "Archive · review before removal",
            ],
            [".build", "2.3 GB", "Hidden · generated build output"],
            ["video-export.mov", "1.7 GB", "Video · personal file"],
          ]) +
          flow(["Sort by size", "Read the impact", "Review selection"])
        );
      case 3:
        return (
          title("Exact duplicates · preserve one copy") +
          fileTable([
            ["design-final.png", "4.2 MB", "Keep this copy ✓"],
            ["design-final-copy.png", "4.2 MB", "Same SHA-256 fingerprint"],
            ["design-final (2).png", "4.2 MB", "Same SHA-256 fingerprint"],
          ]) +
          `<div class="insight-alert">${icon("shield")}<span>One copy always stays.<small>Matching file content matters, not matching names.</small></span></div>`
        );
      case 4:
        return (
          title("Similar photos · local visual matching") +
          `<div class="photo-samples">${[1, 2, 3].map((n) => `<div><i style="--shift:${n * 10}px"></i><span>Similar scene 0${n}</span></div>`).join("")}</div>` +
          flow(["Find similarities", "Compare images", "Choose what stays"])
        );
      case 5:
        return (
          title("Archive an older project") +
          flow([
            "Choose project",
            "Create ZIP copy",
            "Verify archive",
            "Review original",
          ]) +
          rows([
            ["Destination", "External drive / iCloud"],
            ["Verification", "Before removal"],
            ["Original", "Requires your decision"],
          ])
        );
      case 6:
        return (
          title("Mail attachment copies") +
          fileTable([
            ["presentation.pdf", "24 MB", "Downloaded local copy"],
            ["reference.zip", "82 MB", "Review attachment copy"],
            ["images", "36 MB", "Inspect before cleanup"],
          ])
        );
      case 7:
        return (
          title("Trash · a separate final step") +
          rows([
            ["Home Trash", "1.2 GB"],
            ["External drive Trash", "640 MB"],
            ["Easy recovery", "Until Trash is emptied"],
          ]) +
          flow(["Review bins", "Confirm emptying", "Space becomes available"])
        );
      case 8:
        return (
          title("Browser privacy · what changes") +
          rows([
            ["History", "Remove browsing records"],
            ["Cookies", "May sign you out"],
            ["Caches", "Can be downloaded again"],
            ["Passwords & bookmarks", "Excluded ✓"],
          ])
        );
      case 9:
        return (
          title("Shredder · explicit permanent deletion") +
          flow(["Select files", "Review paths", "Confirm permanent removal"]) +
          `<div class="notice">Permanent deletion is separate from default cleanup. Hardware, snapshots, and backups limit secure-erasure guarantees.</div>`
        );
    }
  }
  if (id === "performance") {
    if (index === 0 || index === 1) return processes();
    if (index === 2)
      return (
        title("Idle apps · review before quitting") +
        rows([
          ["Notes", "Idle · 2h", "Sample app, 110 MB"],
          ["Studio", "Idle · 3h", "Sample app, 240 MB"],
          ["Auto-quit", "Opt-in per app"],
        ]) +
        flow(["Find idle apps", "Review work", "Choose to quit"])
      );
    if (index === 3)
      return (
        title("Optimization · recommendations with context") +
        rows([
          [
            "Firewall is off",
            "Review security",
            "High priority in this example",
          ],
          ["Rebuildable caches", "Review cleanup", "Space may be recoverable"],
          ["Memory growth", "Inspect process", "Investigate before quitting"],
        ])
      );
    if (index === 4)
      return (
        title("Maintenance · targeted actions") +
        flow(["Choose a task", "Read the explanation", "Run when needed"]) +
        rows([
          ["DNS cache", "Refresh name lookups"],
          ["Launch Services", "Rebuild app associations"],
          ["Spotlight", "Rebuild the search index"],
        ])
      );
    return (
      title("Startup items · know what starts") +
      rows([
        ["Login item", "Opens with your session"],
        ["Launch agent", "User background job"],
        ["Launch daemon", "System background job"],
      ]) +
      flow(["Inspect", "Stop current run", "Disable future starts"])
    );
  }
  if (id === "developer") {
    if (index === 6) return ports();
    if (index === 1)
      return (
        title("Homebrew · packages & cleanup") +
        rows([
          ["Installed packages", "Inspect"],
          ["Outdated packages", "Review updates"],
          ["Downloaded archives", "Review cleanup"],
        ]) +
        flow(["Inspect package", "Read its purpose", "Choose action"])
      );
    if (index === 2)
      return (
        title("Installed runtimes · example versions") +
        rows([
          ["Node", "v22.x", "JavaScript runtime"],
          ["Python", "3.12.x", "Python runtime"],
          ["Ruby", "3.3.x", "Ruby runtime"],
        ])
      );
    if (index === 3)
      return (
        title("Xcode storage") +
        rows([
          ["DerivedData", "6.4 GB", "Generated build output and indexes"],
          ["Simulators", "12.8 GB", "Development devices and data"],
        ]) +
        flow(["Find storage", "Review project needs", "Rebuild if removed"])
      );
    if (index === 4)
      return (
        title("node_modules · sample discovery") +
        fileTable([
          ["~/projects/studio/node_modules", "1.4 GB", "Dependency folder"],
          ["~/projects/archive/node_modules", "820 MB", "Older project"],
          ["~/projects/site/node_modules", "640 MB", "Dependency folder"],
        ])
      );
    if (index === 5)
      return (
        title("Local services") +
        rows([
          ["Postgres", "Running", "Relational database"],
          ["Redis", "Running", "In-memory data store"],
          ["Service logs", "Available", "Inspect before stopping"],
        ]) +
        flow(["Inspect status", "Read logs", "Start / stop"])
      );
  }
  if (id === "ai") {
    if (index === 0 || index === 1) return cost() + limits();
    if (index === 3)
      return (
        title("Sessions · largest first") +
        rows([
          [
            "Build landing page",
            "480K tokens",
            "Studio · 32 requests · 78% cache",
          ],
          [
            "Investigate build",
            "320K tokens",
            "Tools · 21 requests · 81% cache",
          ],
          ["Refactor module", "180K tokens", "Core · 14 requests · 74% cache"],
        ]) +
        `<p class="lab-footnote">Session names can be renamed locally in MacSweep. Sample sessions shown.</p>`
      );
    if (index === 4) return limits();
    if (index === 5)
      return (
        title("Real Claude limits · explicit opt-in") +
        flow([
          "Enable in Settings",
          "Allow Keychain access",
          "Read Anthropic usage",
        ]) +
        rows([
          ["Token refresh", "Never performed by MacSweep"],
          ["Token storage", "Not stored by MacSweep"],
          ["Request destination", "Anthropic usage endpoint"],
        ])
      );
    if (index === 6)
      return (
        title("Provider service status · sample") +
        rows([
          ["Claude", "Operational · sample"],
          ["OpenAI", "Operational · sample"],
          ["Source", "Public provider status pages"],
        ]) +
        `<p class="lab-footnote">These statuses are illustrations. The Mac app fetches public status information; this page does not poll provider services.</p>`
      );
    if (index === 7)
      return (
        title("Transcript storage · sample age filter") +
        fileTable([
          ["session-a.jsonl", "124 MB", "Older than 90 days"],
          ["session-b.jsonl", "86 MB", "Older than 90 days"],
        ]) +
        `<div class="notice">Moving old transcripts to Trash prevents resuming or searching their local conversation history. Already-counted usage totals remain in MacSweep.</div>`
      );
    if (index === 8)
      return (
        title("AI at a glance") +
        meter("Claude block time", "2h 15m remaining", 45) +
        meter("Codex session", "87% quota left", 87) +
        `<p class="lab-footnote">Choose your preferred tool in Settings → AI. Time remaining and quota remaining are different measurements.</p>`
      );
  }
  if (id === "settings" && index !== 1)
    return (
      title(group.items[index][0] + " · controls explained") +
      rows(settingRows[index]) +
      `<p class="lab-footnote">Illustration of available controls. These labels do not change your Mac’s settings. Choose Appearance to try themes and accents.</p>`
    );
  if (id === "protection") {
    if (index === 3)
      return (
        title("Security audit · sample statuses") +
        rows([
          ["System Integrity Protection", "On ✓"],
          ["Gatekeeper", "On ✓"],
          ["FileVault", "On ✓"],
          ["Firewall", "Off · review"],
          ["XProtect", "On ✓"],
        ])
      );
    if (index === 4)
      return (
        title("App permissions · sample grants") +
        `<div class="process-details">${["Accessibility", "Full Disk Access", "Screen recording", "Microphone", "Camera"].map((n, i) => `<details><summary><span>${n}</span><b>${i + 1} grants</b></summary><div class="process-expanded"><p>Sample app → Allowed</p><p class="lab-footnote">Review the app’s purpose. Use macOS System Settings to revoke access.</p></div></details>`).join("")}</div>`
      );
    if (index === 5)
      return (
        title("Network monitor · sample connections") +
        rows([
          ["Browser", "example.com:443", "HTTPS connection"],
          ["Studio", "127.0.0.1:3000", "Local development"],
          ["Background app", "Remote host", "Inspect identity and purpose"],
        ])
      );
    if (index === 6)
      return (
        title("Sharing & Wi-Fi · sample configuration") +
        rows([
          ["Wi-Fi encryption", "WPA2"],
          ["Remote Login / SSH", "On · review"],
          ["Screen Sharing", "On · review"],
          ["File Sharing", "Off"],
          ["AirDrop", "Contacts only"],
        ])
      );
    if (index === 7)
      return (
        title("Time Machine · backup context") +
        rows([
          ["Most recent backup", "2 hours ago · sample"],
          ["Destination", "Backup drive"],
          ["Excluded folders", "Review exclusions"],
        ]) +
        flow([
          "Check backup age",
          "Review exclusions",
          "Know what is recoverable",
        ])
      );
    if (index === 8)
      return (
        title("Browser extensions · sample permissions") +
        rows([
          ["Reader extension", "Current site only"],
          ["Capture extension", "All sites · review"],
          ["Browser profile", "Work / Personal"],
        ])
      );
  }
  return null;
}

export function bindWidgetEvents(lab) {
  const tree = [
    [
      "Developer",
      "32.6 GB",
      [
        [
          "Xcode",
          "12.8 GB",
          [
            [
              "DerivedData",
              "6.4 GB",
              [
                ["App-build", "3.2 GB"],
                ["Index", "3.2 GB"],
              ],
            ],
            ["Simulators", "6.4 GB"],
          ],
        ],
        [
          "Projects",
          "10.6 GB",
          [
            [
              "Studio",
              "6.2 GB",
              [
                ["node_modules", "3.8 GB"],
                [".build", "1.8 GB"],
                ["src", "0.6 GB"],
              ],
            ],
            ["Prototype", "4.4 GB"],
          ],
        ],
        [
          "Docker",
          "9.2 GB",
          [
            ["Images", "5.2 GB"],
            ["Containers", "1.4 GB"],
            ["Volumes", "2.6 GB"],
          ],
        ],
      ],
    ],
    [
      "Downloads",
      "12.4 GB",
      [
        [
          "Archives",
          "6.8 GB",
          [
            ["project.zip", "4.8 GB"],
            ["reference.zip", "2.0 GB"],
          ],
        ],
        ["Installers", "3.2 GB"],
        ["Media", "2.4 GB"],
      ],
    ],
    [
      "Caches",
      "8.2 GB",
      [
        [
          "Browser",
          "4.2 GB",
          [
            ["Profile cache", "2.4 GB"],
            ["Image cache", "1.8 GB"],
          ],
        ],
        ["Packages", "2.6 GB"],
        ["Other", "1.4 GB"],
      ],
    ],
  ];
  let diskTrail = [];
  const diskItems = () =>
    diskTrail.reduce(
      (items, name) => items.find((item) => item[0] === name)[2],
      tree,
    );
  function paintDisk() {
    lab.querySelector(".deep-treemap").innerHTML = diskItems()
      .map(([name, size, children]) =>
        children
          ? `<button data-folder="${name}"><b>${name}</b><strong>${size}</strong><small>Click to explore →</small></button>`
          : `<div class="treemap-leaf"><b>${name}</b><strong>${size}</strong><small>Sample item · review in the app</small></div>`,
      )
      .join("");
    lab.querySelector(".disk-path").textContent =
      "/" + (diskTrail.length ? " " + diskTrail.join(" / ") : "");
    const back = lab.querySelector("[data-disk-back]");
    back.disabled = diskTrail.length === 0;
    back.textContent = diskTrail.length ? "← Up one folder" : "← Macintosh HD";
  }
  lab.addEventListener("click", async (e) => {
    const folder = e.target.closest("[data-folder]");
    const back = e.target.closest("[data-disk-back]");
    if (folder) {
      // A new storage view starts at the root even if another capability was explored.
      if (lab.querySelector(".disk-path").textContent === "/") diskTrail = [];
      diskTrail.push(folder.dataset.folder);
      paintDisk();
    }
    if (back && diskTrail.length) {
      diskTrail.pop();
      paintDisk();
    }
    const copy = e.target.closest("[data-copy-port]");
    if (copy) {
      try {
        await navigator.clipboard.writeText(
          "http://127.0.0.1:" + copy.dataset.copyPort,
        );
        copy.nextElementSibling.textContent = "Example address copied.";
      } catch {
        copy.nextElementSibling.textContent =
          "Example: http://127.0.0.1:" + copy.dataset.copyPort;
      }
    }
  });
  lab.addEventListener("change", (e) => {
    if (e.target.matches("[data-clean-example]"))
      lab.querySelector(".selection-total").textContent = e.target.checked
        ? "2.6 GB selected · demo only"
        : "Nothing selected";
  });
}
