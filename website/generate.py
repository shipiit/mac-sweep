"""Generate portable HTML entry points with page-specific search and share metadata."""
from pathlib import Path
from html import escape
import json
import hashlib
import os

ROOT = Path(__file__).resolve().parent
ORIGIN = os.environ.get('SITE_ORIGIN', 'https://macsweep-command-center.iamraj.chatgpt.site').rstrip('/')
PAGES = {
    'index': ('MacSweep — A clearer Mac. A better flow.', 'One native Mac app for cleanup, protection, performance, developer tools, AI usage, and system insights.'),
    'features': ('All capabilities — MacSweep', 'Explore Smart Scan, disk cleanup, duplicate detection, security audits, performance tools, and system insights.'),
    'developers': ('For developers — MacSweep', 'Understand Docker, Homebrew, runtimes, Xcode storage, listening ports, local services, Claude Code, and Codex usage.'),
    'trust': ('Privacy & safety — MacSweep', 'Understand on-device processing, cleanup safeguards, PathGuard, quarantine, download checks, and protection limits.'),
    'download': ('Download & setup — MacSweep', 'Download MacSweep for macOS 15 and Apple Silicon. Installation instructions, signing details, and frequently asked questions.'),
}
styles_version = hashlib.sha256((ROOT/'dist/assets/styles.css').read_bytes()).hexdigest()[:10]
features_version = hashlib.sha256((ROOT/'dist/assets/features.css').read_bytes()).hexdigest()[:10]
script_version = hashlib.sha256(b''.join(p.read_bytes() for p in sorted((ROOT/'dist/assets').glob('*.js')))).hexdigest()[:10]
for slug, (title, description) in PAGES.items():
    url = f'{ORIGIN}/{slug}.html'
    markup = f'''<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escape(title)}</title><meta name="description" content="{escape(description)}">
<meta name="theme-color" content="#080a0f"><link rel="icon" href="assets/icon.svg" type="image/svg+xml">
<link rel="canonical" href="{url}">
<meta property="og:type" content="website"><meta property="og:title" content="{escape(title)}">
<meta property="og:description" content="{escape(description)}"><meta property="og:url" content="{url}">
<meta property="og:image" content="{ORIGIN}/assets/social.png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="assets/styles.css?v={styles_version}"><link rel="stylesheet" href="assets/features.css?v={features_version}"><script type="module" src="assets/app.js?v={script_version}"></script>
<script type="application/ld+json">{json.dumps({'@context':'https://schema.org','@type':'SoftwareApplication','name':'MacSweep','operatingSystem':'macOS 15+','applicationCategory':'UtilitiesApplication','description':description,'url':ORIGIN,'downloadUrl':'https://github.com/shipiit/mac-sweep/releases/latest','codeRepository':'https://github.com/shipiit/mac-sweep'})}</script>
</head><body data-page="{slug}"><div id="app"></div><noscript><main style="max-width:800px;margin:80px auto;padding:24px;font-family:system-ui"><h1>{escape(title)}</h1><p>{escape(description)}</p><p>Enable JavaScript to explore the interactive showcase.</p><a href="https://github.com/shipiit/mac-sweep">Read the complete project documentation on GitHub</a><nav><a href="index.html">Overview</a> · <a href="features.html">Capabilities</a> · <a href="developers.html">Developers</a> · <a href="trust.html">Trust</a> · <a href="download.html">Download</a></nav></main></noscript></body></html>'''
    (ROOT / 'dist' / f'{slug}.html').write_text(markup)
print(f'Generated {len(PAGES)} pages in website/dist')
