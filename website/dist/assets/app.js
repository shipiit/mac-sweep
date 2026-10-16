import { initCompanion } from "./companion.js";
import { page } from "./config.js";
import { header, footer } from "./components.js";
import { pages } from "./pages.js";
import { initDemo } from "./demo.js";
import { initFeatureLabs } from "./feature-lab.js";

document.getElementById("app").innerHTML =
  header + `<main id="main">${pages[page] || pages.index}</main>` + footer;

// Navigation and keyboard accessibility.
const menu = document.querySelector(".menu");
menu.addEventListener("click", () => {
  const open = menu.getAttribute("aria-expanded") !== "true";
  menu.setAttribute("aria-expanded", String(open));
  document.querySelector(".navlinks").classList.toggle("open", open);
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    menu.setAttribute("aria-expanded", "false");
    document.querySelector(".navlinks").classList.remove("open");
  }
});
const observer = new IntersectionObserver(
  (entries) =>
    entries.forEach((e) => {
      if (e.isIntersecting) {
        e.target.classList.add("visible");
        observer.unobserve(e.target);
      }
    }),
  { threshold: 0.08 },
);
document.querySelectorAll(".reveal").forEach((e) => observer.observe(e));
let paused = false;
try {
  paused = localStorage.getItem("macsweep-motion") === "paused";
} catch {}
function setMotion(value) {
  paused = value;
  document.body.classList.toggle("motion-paused", value);
  const b = document.getElementById("motion-toggle");
  b.textContent = value ? "▷ Play animations" : "Ⅱ Pause animations";
  b.setAttribute("aria-pressed", String(value));
}
setMotion(paused);
document.getElementById("motion-toggle").addEventListener("click", () => {
  setMotion(!paused);
  try {
    localStorage.setItem("macsweep-motion", paused ? "paused" : "playing");
  } catch {}
});
let toastTimer;
function toast(message) {
  const t = document.querySelector(".toast");
  t.textContent = message;
  t.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("show"), 3200);
}
document.querySelector(".share-button").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(location.href);
    toast("Page link copied. Ready to share.");
  } catch {
    toast("Copy the page URL from your browser to share.");
  }
});

initDemo();

initFeatureLabs();
// Keep the field guide's section navigation in sync with the reader.
const chapters = document.querySelectorAll(".feature-chapter");
if (chapters.length) {
  const chapterObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        document.querySelectorAll(".feature-jump a").forEach((link) => {
          const active = link.hash === "#" + entry.target.id;
          link.classList.toggle("active", active);
          if (active) link.setAttribute("aria-current", "location");
          else link.removeAttribute("aria-current");
        });
      });
    },
    { rootMargin: "-20% 0px -55% 0px" },
  );
  chapters.forEach((chapter) => chapterObserver.observe(chapter));
}

initCompanion();
