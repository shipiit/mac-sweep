import { icon } from "./icons.js";
import { page, REPO } from "./config.js";
const brand = `<a class="brand" href="index.html" aria-label="MacSweep home"><img src="assets/icon.svg" alt="" width="32" height="32">MacSweep</a>`;
const navItems = [
  ["index", "Overview"],
  ["features", "Capabilities"],
  ["developers", "For developers"],
  ["trust", "Trust & safety"],
];
const header = `<a class="skip" href="#main">Skip to content</a><header class="header"><nav class="nav container" aria-label="Main navigation">${brand}<button class="menu" aria-expanded="false" aria-controls="nav-links">Menu</button><div class="navlinks" id="nav-links">${navItems.map(([id, label]) => `<a href="${id}.html" ${page === id ? 'aria-current="page"' : ""}>${label}</a>`).join("")}<a class="btn" href="download.html" ${page === "download" ? 'aria-current="page"' : ""}>Get MacSweep <span aria-hidden="true">↗</span></a></div></nav></header>`;
const footer = `<footer class="footer container"><div class="footer-top">${brand}<div class="footer-links"><a href="features.html">All capabilities</a><a href="trust.html">Privacy & safety</a><a href="https://github.com/shipiit/mac-sweep-website">Website on GitHub ↗</a><button class="share-button motion-toggle">Copy page link ↗</button></div></div><div class="footer-bottom"><span>Made for the Mac. Built with Swift.<br>Independent, native, and built for clarity.</span><button class="motion-toggle" id="motion-toggle" aria-pressed="false">Ⅱ Pause animations</button><span>macOS 15+ · Apple Silicon</span></div></footer><div class="toast" role="status" aria-live="polite"></div>`;
const cta = `<section class="cta"><div class="eyebrow" style="justify-content:center">Less friction. More flow.</div><h2>Your Mac has more to give.</h2><p>Make room for your next idea. Get a clearer view of everything happening on your Mac.</p><div class="actions"><a href="download.html" class="btn primary">Get MacSweep ${icon("download")}</a><a href="features.html" class="btn">Explore all capabilities →</a></div><div class="micro">Native SwiftUI · No third-party dependencies · macOS 15+</div></section>`;
const sectionHead = (eyebrow, title, copy = "") =>
  `<div class="section-head reveal"><div><div class="eyebrow">${eyebrow}</div><h2>${title}</h2></div>${copy ? `<p>${copy}</p>` : ""}</div>`;
const shieldArt = `<div class="privacy-art" aria-hidden="true"><div class="privacy-ring"></div><div class="privacy-ring" style="width:350px;height:350px;animation-direction:reverse;border-style:solid;opacity:.35"></div><div class="shield-shape">${icon("lock")}</div><span class="privacy-caption">ON YOUR MAC. IN YOUR CONTROL.</span></div>`;

export { header, footer, cta, sectionHead, shieldArt };
