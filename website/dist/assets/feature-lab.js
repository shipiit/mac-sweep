import { widgetVisual, bindWidgetEvents } from "./lab-widgets.js";
import { featureGroups } from "./feature-data.js";
import { icon } from "./icons.js";

const labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const bars = (values, names = labels) =>
  `<div class="lab-bars">${values.map((value, i) => `<div class="lab-bar"><div class="bar-track"><i style="--bar:${value}%;--delay:${i * 70}ms"></i><b>${value}</b></div><small>${names[i] || ""}</small></div>`).join("")}</div>`;
const line = `<svg class="lab-line" viewBox="0 0 600 150" preserveAspectRatio="none" role="img" aria-label="Animated sample activity, from low activity through two peaks"><path class="chart-grid" d="M0 25h600M0 65h600M0 105h600M0 145h600"/><path class="trace-fill" d="M0 120 25 115 50 118 75 90 100 105 125 68 150 90 175 38 200 65 225 48 250 90 275 106 300 98 325 115 350 94 375 68 400 82 425 25 450 58 475 38 500 80 525 65 550 95 575 72 600 85V150H0Z"/><path class="trace-line" pathLength="1" d="M0 120 25 115 50 118 75 90 100 105 125 68 150 90 175 38 200 65 225 48 250 90 275 106 300 98 325 115 350 94 375 68 400 82 425 25 450 58 475 38 500 80 525 65 550 95 575 72 600 85"/></svg>`;
function metric(label, value, note) {
  return `<div class="lab-metric"><small>${label}</small><strong>${value}</strong><span>${note}</span></div>`;
}
function visual(group, index) {
  const widget = widgetVisual(group, index);
  if (widget) return widget;
  switch (group.id) {
    case "cleanup":
      return `<div class="lab-toolbar"><span>Macintosh HD <span class="dim">/ sample scan</span></span><span class="live-tag">Review first</span></div><div class="lab-storage"><div class="lab-storage-tile">Developer<small>32.6 GB</small><span>Build output & dependencies</span></div><div class="lab-storage-tile">Downloads<small>12.4 GB</small></div><div class="lab-storage-tile">Caches<small>8.2 GB</small></div><div class="lab-storage-tile">Documents<small>6.1 GB</small></div><div class="lab-storage-tile">Other<small>4.8 GB</small></div></div><div class="lab-process"><span class="scan-sweep"></span>Locate → explain → review → confirm</div><div class="lab-footnote">Rectangle area illustrates storage. These sample sizes are not benchmark results.</div>`;
    case "protection":
      return `<div class="lab-toolbar"><span>Download checks</span><span class="live-tag">Illustrated sequence</span></div><div class="security-sequence">${[
        ["download", "Download", "File completed"],
        ["code", "Inspect", "Check signals"],
        ["shield", "Assess", "Review finding"],
        ["lock", "Quarantine", "If a clear threat"],
      ]
        .map(
          ([i, t, c], n) =>
            `<div style="--step:${n}">${icon(i)}<b>${t}</b><small>${c}</small></div>`,
        )
        .join(
          "",
        )}</div><div class="lab-checks"><span>Signature & Gatekeeper <b>Inspect</b></span><span>Disguised executable <b>Investigate</b></span><span>Quarantined file <b>Restore or delete</b></span></div><div class="lab-footnote">Completed-download checks. Heuristic protection alongside Apple XProtect.</div>`;
    case "performance":
      return `<div class="lab-toolbar"><span>Activity monitor</span><span class="live-tag">Illustrative trace</span></div><div class="lab-metrics">${metric("CPU", "12%", "Processor activity")}${metric("MEMORY", "8.4 GB", "Working memory")}${metric("PRESSURE", "Normal", "Sample status")}</div>${line}<div class="chart-axis"><span>60 seconds ago</span><span>Now</span></div><div class="lab-footnote">The moving line shows how to read a trend. It is not live device telemetry.</div>`;
    case "developer":
      return `<div class="lab-toolbar"><span>Local workspace</span><span class="live-tag">Sample projects</span></div><div class="lab-terminal"><div class="typing-line"><span>❯</span> inspect workspace<span class="terminal-caret">▌</span></div><div class="terminal-code-row"><span>:3000</span><span>node</span><b>~/projects/studio</b></div><div class="terminal-code-row"><span>:5432</span><span>postgres</span><b>Local database</b></div><div class="terminal-code-row"><span>:6379</span><span>redis</span><b>Local cache</b></div><div class="dim" style="margin-top:20px">// Generated data takes room, too.</div></div><div class="lab-capacity"><span>Docker data</span><i style="--fill:66%"></i><b>18.4 GB</b></div><div class="lab-capacity"><span>Build caches</span><i style="--fill:43%"></i><b>9.2 GB</b></div>`;
    case "ai":
      return `<div class="lab-toolbar"><span>Tokens per day</span><label class="lab-filter">Tool <select aria-label="Sample AI provider"><option value="all">All tools</option><option value="claude">Claude Code</option><option value="codex">Codex</option></select></label></div><div class="lab-metrics">${metric("TOKENS", "2.4M", "Input + output + cache")}${metric("API VALUE", "$8.62", "Estimate, not a bill")}${metric("SESSIONS", "12", "Across 6 projects")}</div><div class="provider-chart">${bars([35, 56, 43, 78, 60, 92, 68])}</div><div class="lab-footnote"><span class="legend-dot"></span> Sample daily tokens · Choose a provider to compare illustrative activity.</div>`;
    case "applications":
      return `<div class="lab-toolbar"><span>Application inventory</span><span class="live-tag">Illustrative apps</span></div><div class="app-orbit-grid">${[
        ["S", "Studio", "3h 12m"],
        ["B", "Browser", "1h 48m"],
        ["T", "Terminal", "54m"],
        ["N", "Notes", "32m"],
      ]
        .map(
          ([s, t, time], i) =>
            `<div style="--delay:${i * 120}ms"><i>${s}</i><b>${t}</b><small>${time} active today</small><span class="app-usage" style="--fill:${85 - i * 18}%"></span></div>`,
        )
        .join(
          "",
        )}</div><div class="lab-footnote">Example app names and local time totals. App usage is optional in Settings.</div>`;
    case "insights":
      return `<div class="lab-toolbar"><span>Disk growth comparison</span><span class="live-tag">Two sample scans</span></div><div class="comparison-bars"><div><span>Developer</span><div><i style="--fill:45%"></i><i style="--fill:77%"></i></div><b>+8.6 GB</b></div><div><span>Downloads</span><div><i style="--fill:25%"></i><i style="--fill:48%"></i></div><b>+4.2 GB</b></div><div><span>Documents</span><div><i style="--fill:39%"></i><i style="--fill:42%"></i></div><b>+0.8 GB</b></div></div><div class="lab-legend"><span>● Earlier scan</span><span>● Later scan</span></div><div class="insight-alert">${icon("chart")}<span>A little context goes a long way.<small>A comparison tells you where to investigate.</small></span></div>`;
    case "settings":
      return `<div class="lab-toolbar"><span>Appearance playground</span><span class="live-tag">Demo preferences</span></div><div class="theme-controls" role="group" aria-label="Sample appearance"><button class="theme-chip selected" data-theme="dark" aria-pressed="true">Dark</button><button class="theme-chip" data-theme="light" aria-pressed="false">Light</button><span>Accent</span>${["#8da7ff", "#8bdac6", "#d9a2ec", "#efa87d"].map((color, i) => `<button class="accent-chip ${i === 0 ? "selected" : ""}" style="--swatch:${color}" data-accent="${color}" aria-label="${["Blue", "Mint", "Purple", "Orange"][i]} demo accent" aria-pressed="${i === 0}"></button>`).join("")}</div><div class="settings-mini"><aside><i></i><span></span><span></span><span></span></aside><div><b>Your dashboard</b><div class="settings-mini-cards"><span>CPU<strong>12%</strong></span><span>Memory<strong>8.4 GB</strong></span><span class="demo-port-card">Ports<strong>3</strong></span></div></div></div><label class="demo-switch-row"><span>Show Ports card <small>Only changes this illustration</small></span><input type="checkbox" class="demo-switch" checked aria-label="Show Ports card in demo"></label>`;
    default:
      return "";
  }
}
export function featureLab(group) {
  return `<div class="feature-lab" data-lab="${group.id}"><div class="lab-titlebar"><span>${icon("spark")} Explore ${group.label}</span><small>INTERACTIVE UI ILLUSTRATION · SAMPLE DATA</small></div><div class="lab-layout"><div class="lab-selectors" role="tablist" aria-label="${group.label} capabilities">${group.items.map(([name], i) => `<button role="tab" aria-selected="${i === 0}" tabindex="${i === 0 ? 0 : -1}" id="lab-${group.id}-${i}" aria-controls="lab-panel-${group.id}" data-feature-index="${i}"><span>${String(i + 1).padStart(2, "0")}</span>${name}<b aria-hidden="true">↗</b></button>`).join("")}</div><div id="lab-panel-${group.id}" class="lab-content" role="tabpanel" tabindex="0" aria-labelledby="lab-${group.id}-0"><div class="lab-explanation"><span class="eyebrow">What it does</span><h3>${group.items[0][0]}</h3><p>${group.items[0][1]}</p></div><div class="lab-visual">${visual(group, 0)}</div><div class="plain-english"><span>IN EVERYDAY TERMS</span><p>${group.items[0][2]}</p></div></div></div><div class="lab-glossary"><h3>Make sense of the terms.</h3><p>Open a term for a plain-language explanation.</p><div>${group.terms.map(([term, meaning]) => `<details><summary>${term}</summary><p>${meaning}</p></details>`).join("")}</div></div></div>`;
}
export function initFeatureLabs() {
  document.querySelectorAll("[data-lab]").forEach((lab) => {
    const group = featureGroups.find((g) => g.id === lab.dataset.lab);
    const buttons = [...lab.querySelectorAll("[data-feature-index]")];
    bindWidgetEvents(lab);
    function select(index, focus = false) {
      buttons.forEach((b, i) => {
        b.setAttribute("aria-selected", String(i === index));
        b.tabIndex = i === index ? 0 : -1;
      });
      const [name, description, explanation] = group.items[index];
      const panel = lab.querySelector("[role=tabpanel]");
      panel.setAttribute("aria-labelledby", `lab-${group.id}-${index}`);
      panel.querySelector(".lab-explanation h3").textContent = name;
      panel.querySelector(".lab-explanation p").textContent = description;
      panel.querySelector(".plain-english p").textContent = explanation;
      panel.querySelector(".lab-visual").innerHTML = visual(group, index);
      initControls(lab);
      panel.classList.remove("lab-changed");
      void panel.offsetWidth;
      panel.classList.add("lab-changed");
      if (focus) buttons[index].focus();
    }
    buttons.forEach((b, i) => {
      b.addEventListener("click", () => select(i));
      b.addEventListener("keydown", (e) => {
        let next;
        if (["ArrowDown", "ArrowRight"].includes(e.key))
          next = (i + 1) % buttons.length;
        if (["ArrowUp", "ArrowLeft"].includes(e.key))
          next = (i + buttons.length - 1) % buttons.length;
        if (e.key === "Home") next = 0;
        if (e.key === "End") next = buttons.length - 1;
        if (next !== undefined) {
          e.preventDefault();
          select(next, true);
        }
      });
    });
    initControls(lab);
  });
}
function initControls(lab) {
  lab.querySelector("select")?.addEventListener("change", (e) => {
    const values = {
      all: [35, 56, 43, 78, 60, 92, 68],
      claude: [24, 40, 30, 55, 41, 67, 48],
      codex: [11, 16, 13, 23, 19, 25, 20],
    };
    lab.querySelector(".provider-chart").innerHTML = bars(
      values[e.target.value],
    );
    const numbers = {
      all: ["2.4M", "$8.62", "12"],
      claude: ["1.6M", "$6.14", "8"],
      codex: ["0.8M", "$2.48", "4"],
    };
    lab
      .querySelectorAll(".lab-metric strong")
      .forEach((n, i) => (n.textContent = numbers[e.target.value][i]));
  });
  lab.querySelectorAll("[data-theme]").forEach((b) =>
    b.addEventListener("click", () => {
      lab
        .querySelector(".settings-mini")
        .classList.toggle("light", b.dataset.theme === "light");
      lab.querySelectorAll("[data-theme]").forEach((t) => {
        t.classList.toggle("selected", t === b);
        t.setAttribute("aria-pressed", String(t === b));
      });
    }),
  );
  lab.querySelectorAll("[data-accent]").forEach((b) =>
    b.addEventListener("click", () => {
      lab
        .querySelector(".settings-mini")
        .style.setProperty("--demo-accent", b.dataset.accent);
      lab.querySelectorAll("[data-accent]").forEach((t) => {
        t.classList.toggle("selected", t === b);
        t.setAttribute("aria-pressed", String(t === b));
      });
    }),
  );
  lab
    .querySelector(".demo-switch")
    ?.addEventListener(
      "change",
      (e) => (lab.querySelector(".demo-port-card").hidden = !e.target.checked),
    );
}
