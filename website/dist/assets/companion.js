import { icon } from "./icons.js";
const ring = (label, value, color) =>
  `<div class="hud-stat"><div style="--ring:${value}%;--ring-color:${color}"><b>${value}%</b></div><small>${label}</small></div>`;
const hudPanels = {
  system: `<div class="hud-rings">${ring("CPU", 18, "#7dcbab")}${ring("Memory", 64, "#e6ad79")}${ring("Disk", 58, "#8fa8ef")}${ring("Battery", 100, "#7dcbab")}</div><div class="hud-status">Thermal: cool <span>Memory pressure: normal</span></div>`,
  apps: `<div class="hud-list"><span>Browser <b>1.4 GB</b></span><span>Studio <b>820 MB</b></span><span>Terminal <b>120 MB</b></span></div><p>Top memory at a glance. Inspect full process groups in the Mac app.</p>`,
  ports: `<div class="hud-list"><span><em>:3000</em> node <b>This Mac</b></span><span><em>:5432</em> postgres <b>This Mac</b></span><span><em>:8080</em> python <b>Network</b></span></div><p>See what is listening, then open the full Ports page for commands and project paths.</p>`,
  ai: `<div class="hud-list"><span>Claude Code <b>1.6M tokens</b></span><span>Codex <b>0.8M tokens</b></span><span>API-equivalent value <b>$8.62</b></span></div><p>Choose which tool’s limits appear here in Settings → AI.</p>`,
  clean: `<div class="hud-list"><span>Rebuildable caches <b>2.6 GB</b></span><span>Review first <b>4.8 GB</b></span><span>Default cleanup <b>Move to Trash</b></span></div><p>Open cleanup to inspect recommendations and confirm actions. Nothing is removed by this demo.</p>`,
};
export const companionShowcase = `<section class="section container companion-section" id="always-there"><div class="section-head reveal"><div><div class="eyebrow">A little closer to your workflow</div><h2>Big picture.<br>Small, thoughtful spaces.</h2></div><p>Hover or tap the notch. Open the menu bar. Explore System, Apps, Ports, AI, and Clean without losing the bigger picture.</p></div><div class="macbook-demo reveal"><div class="macbook-screen"><div class="mock-menu"><span>◈ &nbsp; <b>MacSweep</b> <i>File &nbsp; Edit &nbsp; View</i></span><button class="menu-bar-trigger" data-open-menubar aria-expanded="false" aria-label="Open MacSweep menu bar demo">${icon("pulse")}<span>CPU 18%<br>MEM 64%</span></button></div><div class="mock-dashboard"><div class="mock-sidebar"><img src="assets/icon.svg" width="24" height="24" alt=""><span>Smart Scan</span><span class="selected">Dashboard</span><span>AI Usage</span><small>CLEANUP</small><span>Space & Junk</span><span>Large Files</span><small>DEVELOPER</small><span>Developer</span><span>Ports</span></div><div class="mock-main"><div class="mock-machine"><span>${icon("pulse")}<b>Your Mac, in focus.</b><small>Native tools. One clear picture.</small></span><div class="mock-gauges">${ring("CPU", 18, "#7dcbab")}${ring("Memory", 64, "#e6ad79")}${ring("Disk", 58, "#8fa8ef")}</div></div><div class="mock-activity"><span>System activity <small>CPU & memory · sample data</small></span><svg viewBox="0 0 600 100" preserveAspectRatio="none" aria-hidden="true"><path d="M0 30 30 29 60 32 90 27 120 30 150 28 180 31 210 29 240 30 270 27 300 32 330 29 360 30 390 28 420 32 450 29 480 28 510 30 540 28 570 31 600 29V100H0Z" fill="#b887e71a" stroke="#b887e7" stroke-width="1.5"/><path class="desktop-trace" d="M0 80 20 70 40 75 60 48 80 61 100 30 120 69 140 64 160 72 180 68 200 84 220 65 240 30 260 55 280 70 300 75 320 62 340 78 360 71 380 83 400 66 420 74 440 60 460 80 480 70 500 76 520 60 540 80 560 70 580 75 600 65" fill="none" stroke="#7da6fa" stroke-width="2"/></svg></div><div class="mock-bottom"><div>Storage<strong>186 GB</strong><small>Available</small></div><div>Memory<strong>Normal</strong><small>Pressure</small></div><div>Battery<strong>100%</strong><small>Plugged in</small></div><div>Network<strong>Wi-Fi</strong><small>Connected</small></div></div></div></div><div class="notch-zone"><button class="notch-trigger" data-open-notch aria-label="Expand MacSweep notch demo" aria-expanded="false"><span class="notch-camera"></span><span>18% &nbsp; CPU &nbsp; 64% MEM</span></button><div class="notch-expanded" hidden><div class="hud-tabs" role="tablist" aria-label="Notch demo views">${[
  ["system", "System"],
  ["apps", "Apps"],
  ["ports", "Ports"],
  ["ai", "AI"],
  ["clean", "Clean"],
]
  .map(
    ([id, label], i) =>
      `<button role="tab" id="hud-${id}" data-hud="${id}" aria-selected="${i === 0}" tabindex="${i === 0 ? 0 : -1}" aria-controls="hud-panel">${label}</button>`,
  )
  .join(
    "",
  )}<button class="close-hud" data-close-notch aria-label="Close notch demo">×</button></div><div id="hud-panel" class="hud-panel" role="tabpanel" aria-labelledby="hud-system">${hudPanels.system}</div></div></div><div class="menubar-popup" hidden><div class="popup-heading"><b>MacSweep</b><button data-close-menubar aria-label="Close menu bar demo">×</button></div><span class="popup-caption">Your Mac · sample data</span><div class="popup-grid"><div>Storage<b>186 GB free</b><small>2.6 GB to review</small></div><div>Memory<b>Normal</b><small>Pressure</small></div><div>Battery<b>100%</b><small>Health 91%</small></div><div>CPU<b>18%</b><small>Cool</small></div><div>Wi-Fi<b>28 KB/s ↓</b><small>6 KB/s ↑</small></div><div>AI today<b>2.4M tokens</b><small>API value $8.62</small></div></div><div class="popup-ports"><small>LISTENING PORTS</small><span>:3000 &nbsp; node <b>This Mac</b></span><span>:5432 &nbsp; postgres <b>This Mac</b></span></div><a href="features.html#insights">Explore all insights →</a></div><div class="mock-dock" aria-hidden="true"><i>F</i><i>◉</i><i>⌘</i><i>✧</i><i>▤</i><i>◈</i></div></div><div class="macbook-base"></div></div><div class="companion-controls"><button class="btn" data-remote-notch>Explore the notch ${icon("arrow")}</button><button class="btn" data-remote-menu>Open menu bar ${icon("arrow")}</button></div><p class="demo-caption">Recreated from the Mac app with sample data. Click a view to explore; these controls only change the illustration.</p></section>`;
export function initCompanion() {
  document.querySelectorAll(".companion-section").forEach((section) => {
    const zone = section.querySelector(".notch-zone"),
      expanded = section.querySelector(".notch-expanded"),
      trigger = section.querySelector("[data-open-notch]"),
      popup = section.querySelector(".menubar-popup"),
      menu = section.querySelector("[data-open-menubar]");
    const openNotch = (value) => {
      expanded.hidden = !value;
      trigger.setAttribute("aria-expanded", String(value));
      zone.classList.toggle("expanded", value);
    };
    const openMenu = (value) => {
      popup.hidden = !value;
      menu.setAttribute("aria-expanded", String(value));
    };
    // Pointer hover expands the notch; touch and keyboard users use the buttons.
    trigger.addEventListener("pointerenter", (e) => {
      if (e.pointerType === "mouse") openNotch(true);
    });
    section.addEventListener("click", (e) => {
      if (e.target.closest("[data-open-notch],[data-remote-notch]")) {
        openNotch(true);
        openMenu(false);
      }
      if (e.target.closest("[data-close-notch]")) openNotch(false);
      if (e.target.closest("[data-open-menubar],[data-remote-menu]")) {
        openMenu(popup.hidden);
        openNotch(false);
      }
      if (e.target.closest("[data-close-menubar]")) openMenu(false);
      if (e.target.closest("[data-remote-notch],[data-remote-menu]")) {
        section
          .querySelector(".macbook-screen")
          .scrollIntoView({
            behavior:
              document.body.classList.contains("motion-paused") ||
              matchMedia("(prefers-reduced-motion: reduce)").matches
                ? "instant"
                : "smooth",
            block: "center",
          });
      }
      const tab = e.target.closest("[data-hud]");
      if (tab) selectHud(tab.dataset.hud);
    });
    function selectHud(id) {
      section.querySelector(".hud-panel").innerHTML = hudPanels[id];
      section
        .querySelector(".hud-panel")
        .setAttribute("aria-labelledby", "hud-" + id);
      section.querySelectorAll("[data-hud]").forEach((t) => {
        const active = t.dataset.hud === id;
        t.setAttribute("aria-selected", String(active));
        t.tabIndex = active ? 0 : -1;
      });
    }
    const tabs = [...section.querySelectorAll("[data-hud]")];
    tabs.forEach((t, i) =>
      t.addEventListener("keydown", (e) => {
        let n;
        if (e.key === "ArrowRight") n = (i + 1) % tabs.length;
        if (e.key === "ArrowLeft") n = (i + tabs.length - 1) % tabs.length;
        if (n !== undefined) {
          e.preventDefault();
          selectHud(tabs[n].dataset.hud);
          tabs[n].focus();
        }
      }),
    );
    section.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        openMenu(false);
        openNotch(false);
        trigger.focus();
      }
    });
  });
}
