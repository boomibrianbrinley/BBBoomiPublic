# Boomi Toolkit (Browser Script)

[`boomi-toolkit-core.min.js`](boomi-toolkit-core.min.js) is a minified, unofficial browser script that injects a floating toolkit panel into the Boomi AtomSphere UI, adding a set of quality-of-life features grouped by area:

- **Build** — copy component ID/URL/XML, extract Set Properties from every Set Properties shape on the canvas (exportable as TSV), single-click folder expand, collapse all folders, chooser input tooltips, restore hidden Close button, fix modal button order, highlight log severity, toggle table text wrap, label tabs by section.
- **Extension Designer** — select every visible checkbox in the Extension Designer dialog at once.
- **Deploy & Packaging** — sync packaging notes into the deployment notes field, arm a save/confirm reminder before packaging, schedule setup reminder banner.
- **Process Reporting** — jump to the 7-day dashboard view, open Process Reporting pre-filtered to the component you have open in Build, auto-refresh on a configurable interval.
- **General** — copy your Boomi account ID from the page, open nav menu links in a new tab.

Running it again while already loaded toggles the panel rather than re-injecting it (`window.__boomiToolkit.toggle()`).

## Loading it

This is unofficial, client-side-only tooling — it doesn't call any Boomi API. Since it's shipped minified, review the source before trusting it in your browser. It's designed to be injected into an open AtomSphere tab; the most direct way is pasting its contents into your browser's DevTools console while on an AtomSphere page. If you have a preferred bookmarklet or userscript-manager (e.g. Tampermonkey) wrapper for it, document that here.

## Note

The source is minified, so it isn't reviewable as committed — treat this file as a build artifact. If the un-minified source lives elsewhere, consider linking to it here for anyone who wants to audit or modify it.
