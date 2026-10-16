import { icon } from "./icons.js";
const chartSvg = `<svg viewBox="0 0 640 100" preserveAspectRatio="none" role="img" aria-label="Illustrative CPU activity chart"><defs><linearGradient id="area" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#6f8df4" stop-opacity=".25"/><stop offset="1" stop-color="#6f8df4" stop-opacity="0"/></linearGradient></defs><path d="M0 25H640M0 55H640M0 85H640" stroke="#ffffff08" fill="none"/><path d="M0 78 18 76 32 80 48 67 65 72 82 55 96 62 110 51 126 56 140 30 155 47 171 39 186 60 204 56 220 70 236 67 251 77 270 65 288 72 307 47 320 57 335 35 350 44 367 23 381 38 395 26 410 55 428 50 441 67 460 58 479 62 496 41 515 48 532 29 550 40 568 32 587 48 605 39 622 50 640 38V100H0Z" fill="url(#area)"/><path d="M0 78 18 76 32 80 48 67 65 72 82 55 96 62 110 51 126 56 140 30 155 47 171 39 186 60 204 56 220 70 236 67 251 77 270 65 288 72 307 47 320 57 335 35 350 44 367 23 381 38 395 26 410 55 428 50 441 67 460 58 479 62 496 41 515 48 532 29 550 40 568 32 587 48 605 39 622 50 640 38" stroke="#8da7ff" stroke-width="2" fill="none"/></svg>`;
const demo = `<div class="demo-shell reveal" id="demo"><div class="demo-top"><div class="traffic" aria-hidden="true"><i></i><i></i><i></i></div>MacSweep — interactive preview</div><div class="demo-body"><div class="demo-nav" role="tablist" aria-label="Explore MacSweep"><div class="brand"><img src="assets/icon.svg" alt="">MacSweep</div><small>YOUR MAC</small>${[
  ["overview", "Overview", "pulse"],
  ["scan", "Smart Scan", "spark"],
  ["storage", "Space & Junk", "disk"],
  ["security", "Protection", "shield"],
  ["developer", "Developer", "code"],
  ["ai", "AI Usage", "ai"],
]
  .map(
    ([id, label, i], n) =>
      `<button class="demo-tab" id="tab-${id}" role="tab" aria-selected="${n === 0}" tabindex="${n === 0 ? 0 : -1}" aria-controls="demo-panel" data-demo="${id}">${icon(i)}${label}</button>`,
  )
  .join(
    "",
  )}</div><div class="demo-panel" id="demo-panel" role="tabpanel" aria-labelledby="tab-overview" tabindex="0"></div></div></div><p class="demo-caption">An interactive illustration of MacSweep. Sample data, never your device. Select a module to explore.</p>`;
function stat(label, value, unit, foot) {
  return `<div class="stat"><small>${label}</small><strong>${value} <em>${unit}</em></strong><div class="stat-foot">${foot}</div></div>`;
}
const panels = {
  overview: `<div class="panel-heading"><div><h3>A little clarity. A lot of control.</h3><p>Your Mac, at a glance.</p></div><span class="live-tag">● Sample system</span></div><div class="stat-grid">${stat("CPU LOAD", "12", "%", "Low activity")}${stat("MEMORY", "8.4", "GB", "Pressure: normal")}${stat("DISK AVAILABLE", "186", "GB", "Plenty of room")}</div><div class="chart"><div class="chart-head"><span>System activity</span><span style="color:#819bf2">● CPU</span></div>${chartSvg}<div class="chart-axis"><span>60 seconds ago</span><span>Now</span></div></div>`,
  scan: `<div class="panel-heading"><div><h3>One scan. A clearer picture.</h3><p>Junk, security, speed, and apps — together.</p></div><span class="live-tag">Illustrative demo</span></div><div class="scan-display"><div class="scan-ring" style="--progress:0"><strong id="scan-percent">Ready</strong></div><div class="scan-results" id="scan-results">Space & junk <b>— waiting</b><br>Security checks <b>— waiting</b><br>Performance <b>— waiting</b><br>Applications <b>— waiting</b></div></div><div class="scan-controls"><button class="btn primary" id="start-scan">Run demo scan ${icon("spark")}</button><button class="btn" id="stop-scan" hidden>Stop scan</button></div><p class="micro" id="scan-status" role="status" aria-live="polite" style="text-align:center">This demo does not access or change any files.</p>`,
  storage: `<div class="panel-heading"><div><h3>See where your space goes.</h3><p>Hidden folders included. Every recommendation explained.</p></div><span class="live-tag">Sample disk map</span></div><div class="treemap"><div>Developer<small>32.6 GB</small></div><div>Downloads<small>12.4 GB</small></div><div>Caches<small>8.2 GB</small></div><div>Documents<small>6.1 GB</small></div><div>Other<small>4.8 GB</small></div></div><div class="check-lines" style="margin-top:22px"><span>Safe to remove <b>Rebuildable caches</b></span><span>Review first <b>You decide what stays</b></span><span>Default cleanup <b>Move to Trash</b></span></div>`,
  security: `<div class="panel-heading"><div><h3>More visibility. Fewer surprises.</h3><p>Understand the protections already on your Mac.</p></div><span class="live-tag">Sample audit</span></div><div class="stat-grid">${stat("GATEKEEPER", "On", "", "App verification")}${stat("FILEVAULT", "On", "", "Disk encryption")}${stat("FIREWALL", "On", "", "Connection filtering")}</div><div class="check-lines" style="margin-top:28px"><span>Download protection <b>Checks completed downloads</b></span><span>Suspicious files <b>Review or quarantine</b></span><span>App permissions <b>Camera, mic & more</b></span><span>Network monitor <b>Connections per app</b></span></div><p class="micro">Heuristic checks alongside XProtect. Not a signature antivirus.</p>`,
  developer: `<div class="panel-heading"><div><h3>From “what’s running?” to “got it.”</h3><p>Ports, projects, packages, and services in one place.</p></div><span class="live-tag">Sample workspace</span></div><table class="table"><thead><tr><th>PORT</th><th>PROCESS</th><th>PROJECT</th><th>STATE</th></tr></thead><tbody><tr><td>3000</td><td>node</td><td>~/projects/studio</td><td>● Listening</td></tr><tr><td>5432</td><td>postgres</td><td>Local database</td><td>● Running</td></tr><tr><td>6379</td><td>redis-server</td><td>Local cache</td><td>● Running</td></tr></tbody></table><div class="pill-row"><span class="pill">Docker storage</span><span class="pill">Homebrew</span><span class="pill">Xcode</span><span class="pill">node_modules</span></div>`,
  ai: `<div class="panel-heading"><div><h3>Your AI workflow, in focus.</h3><p>Claude Code and Codex, across projects and sessions.</p></div><span class="live-tag">Sample usage</span></div><div class="stat-grid">${stat("TOKENS TODAY", "2.4", "M", "Across local sessions")}${stat("API-EQUIVALENT", "$8.62", "", "Estimate, not your bill")}${stat("ACTIVE PROJECTS", "6", "", "Usage by project")}</div><div class="ai-bars"><div class="ai-bar"><label>Claude Code <span>1.6M tokens</span></label><i style="--width:67%"></i></div><div class="ai-bar"><label>Codex <span>0.8M tokens</span></label><i style="--width:33%"></i></div></div><p class="micro">Explore by model, session, and project. View limits and service status.</p>`,
};

export { demo, panels };
export function initDemo() {
  // The product preview uses sample data and never inspects the visitor’s device.
  let scanTimer;
  function activateDemo(id) {
    clearInterval(scanTimer);
    const panel = document.getElementById("demo-panel");
    if (!panel) return;
    panel.innerHTML = panels[id];
    panel.setAttribute("aria-labelledby", `tab-${id}`);
    document.querySelectorAll(".demo-tab").forEach((t) => {
      const active = t.dataset.demo === id;
      t.setAttribute("aria-selected", String(active));
      t.tabIndex = active ? 0 : -1;
    });
    if (id === "scan") setupScan();
  }
  const tabs = [...document.querySelectorAll(".demo-tab")];
  tabs.forEach((t, index) => {
    t.addEventListener("click", () => activateDemo(t.dataset.demo));
    t.addEventListener("keydown", (e) => {
      let next;
      if (e.key === "ArrowRight" || e.key === "ArrowDown")
        next = (index + 1) % tabs.length;
      if (e.key === "ArrowLeft" || e.key === "ArrowUp")
        next = (index + tabs.length - 1) % tabs.length;
      if (e.key === "Home") next = 0;
      if (e.key === "End") next = tabs.length - 1;
      if (next !== undefined) {
        e.preventDefault();
        tabs[next].focus();
        activateDemo(tabs[next].dataset.demo);
      }
    });
  });
  function setupScan() {
    const start = document.getElementById("start-scan"),
      stop = document.getElementById("stop-scan"),
      status = document.getElementById("scan-status");
    let progress = 0;
    function paint() {
      document
        .querySelector(".scan-ring")
        .style.setProperty("--progress", progress);
      document.getElementById("scan-percent").textContent = progress + "%";
      document.getElementById("scan-results").innerHTML = [
        ["Space & junk", "12.6 GB to review", 25],
        ["Security checks", "Checks complete", 50],
        ["Performance", "2 suggestions", 75],
        ["Applications", "Review complete", 100],
      ]
        .map(
          ([name, result, limit]) =>
            `${name} <b>— ${progress >= limit ? result : "scanning…"}</b>`,
        )
        .join("<br>");
    }
    start.addEventListener("click", () => {
      clearInterval(scanTimer);
      progress = 0;
      paint();
      start.disabled = true;
      stop.hidden = false;
      status.textContent =
        "Demo scan in progress. No files are being accessed.";
      scanTimer = setInterval(() => {
        progress = Math.min(progress + 2, 100);
        paint();
        if (progress === 100) {
          clearInterval(scanTimer);
          start.disabled = false;
          start.textContent = "Run again";
          stop.hidden = true;
          status.textContent =
            "Demo complete. Review recommendations before taking action in the Mac app.";
        }
      }, 75);
    });
    stop.addEventListener("click", () => {
      clearInterval(scanTimer);
      start.disabled = false;
      start.textContent = "Restart demo scan";
      stop.hidden = true;
      status.textContent = "Demo scan stopped. Nothing was changed.";
    });
  }
  activateDemo("overview");
}
