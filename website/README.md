# MacSweep showcase

Five responsive pages: overview, capabilities, developer tools, trust, and download/setup.

## Preview

From this directory:

```sh
python3 -m http.server 4173 --directory dist --bind 127.0.0.1
```

Open http://127.0.0.1:4173. Deploy `dist/` to any static host. No package installation or compilation is required.

## Files

- `dist/assets/styles.css`: responsive design, orbital artwork, motion, and reduced-motion support.
- `dist/assets/app.js`: page initialization, navigation behavior, scroll reveals, motion controls, and clipboard sharing.
- `dist/assets/icon.svg`: vector artwork based on the app's indigo/cyan gauge-and-sparkle identity.
- `generate.py`: regenerates the five HTML entry points with page-specific metadata.

The interactive preview contains clearly labelled sample data. It does not inspect the visitor's Mac. Product descriptions are grounded in the repository README and Swift implementation. Download links open the project’s GitHub releases; no release version or download count is hard-coded.

Motion respects `prefers-reduced-motion` and can be paused using the footer control. UI uses semantic landmarks, keyboard-accessible tabs, visible focus, and native FAQ disclosure controls.

Fonts are loaded from Google Fonts, with local sans-serif fallbacks. No analytics are included.

## Interactive field guide

The Capabilities page covers 57 selectable explanations across 8 areas, with 37 plain-language term definitions. Modules:

- `feature-data.js`: source-grounded product explanations, practical context, and glossary.
- `feature-page.js`: field-guide page composition.
- `feature-lab.js`: accessible per-section tabs and browser-local appearance controls.
- `lab-widgets.js`: storage drill-down, process groups, port details, and feature-specific UI illustrations.
- `companion.js`: MacBook illustration, five-view notch HUD, and menu bar popover.
- `features.css`: interactive guide and companion layouts, graph motion, responsive behavior.
- `components.js`, `icons.js`, `config.js`: shared UI, SVG symbols, and project links.
- `demo.js`: six-module overview and the start/stop scan demonstration.

The supplied app screenshots inform the illustrations. Personal screenshots, user paths, IP addresses, and usage figures are not included in the site. All displayed activity is sample data.

## Verification

Browser checks cover all 57 capability tabs, storage drill-down/back/selection, expandable processes, port details, theme/accent controls, dashboard card visibility, notch/menu-bar behavior, scan start/stop/completion, navigation, FAQs, and mobile overflow. Motion honors the system preference and the footer's pause control.

## GitHub Pages

The public `shipiit/mac-sweep-website` repository contains only the contents of this directory, excluding `.openai/`. Its Actions workflow publishes `dist/` on pushes to `main`. The private Mac app source remains in `shipiit/mac-sweep`; releases and source links require repository access.

The workflow sets `SITE_ORIGIN` from GitHub Pages configuration when running `generate.py`, so canonical and social-sharing URLs work under the project subpath. Existing relative navigation and asset paths also work under that subpath.
