# Kernel Atlas

Build a complete, local macOS codebase explorer inspired by Makepad Scope.

## Acceptance
- Launchable native Apple Silicon `.app`, with source, build script, and no paid services.
- A complete Linux codebase below 20,000,000 bytes, measured after extraction; bundled provenance and license.
- Honest, source-backed file / function / call exploration, search, readable code, and curated journeys.
- Attractive 3D city and legible 2D map; pan, zoom, focus, stable subsystem colors, contextual connections.
- Measured startup, memory and rendering; idle rendering stops; screenshot and interaction checks.

## Sequence
1. Complete: verify upstream and select / measure the corpus.
2. Complete: build reproducible offline index and validate its relationships.
3. Complete: build the native app and refine its visual composition on this device.
4. Complete: final installed-app interaction check and packaging.

## Design
The map is the centerpiece, surrounded by quiet native chrome. Dark mineral blue
(`#101C2C`) grounds a luminous, architectural model. Subsystems use sea glass
(`#69C8B1`), cornflower (`#7EABEE`), amber (`#E9B971`), lilac (`#BAA0DE`), and
coral (`#E38D89`). SF Pro handles navigation; New York supplies a restrained
editorial title; SF Mono is reserved for actual source and paths.

Layout: narrow left subsystem/journey rail | expansive interactive model | source inspector.
Top: corpus identity and view controls. Bottom: meaningful encoding legend and live status.

Taste choices: no decorative animation, no permanent spaghetti graph, no randomly
assigned heights, no unreadable labels on tiny tiles. Stable area encoding, meaningful
height, selection-driven edges, and source-linked guided routes provide the improvements.
Native AppKit/SwiftUI and a Metal-backed SceneKit view target this Mac without shipping
a browser runtime. This is an original implementation, not the private Scope app.


## Evidence
- Complete official corpus: 561 files / 4,719,743 bytes; archive checksum matched.
- Five index tests passed: content hashes, source-backed calls, parser fixtures,
  layout proportions/non-overlap, historical entrypoints.
- Native installed app: 14 checks passed, including Metal, hit testing, source,
  search, journeys, graph arcs, 2D flattening and overhead camera geometry.
- UI: boot journey -> start_kernel at line 351; search do_page_fault -> line 886;
  Calls -> do_wp_page at line 616; native save dialog -> evidence/ui-map.png.
- Fixed an overhead-camera singularity discovered by inspecting exported images.
- Final close-up polish: readable screen-space labels and metric-aware captions.
- Installed app: ~/Applications/Kernel Atlas.app; local ad-hoc signature verified.
- Runtime and screenshot receipts: evidence/installed/; packaged zip: dist/.
- No paid or cloud compute was used.

## Follow-up: source inside the map
Complete: actual complete source appears within every sufficiently enlarged file
box, with line numbers, syntax, progressive detail, and deeper pointer-centered zoom.
Only visible rows are drawn; prepared documents and shaped rows have bounded caches.
Column breaks keep nearby function definitions with their bodies where possible.

- Final installed build passes 25 native checks, including unselected source,
  middle and last lines, pointer anchor, cache bounds and exposed 3D roofs.
- Source composition: 5.75 ms median / 6.68 ms p95 at 938×678, warm cache,
  including scene readback and CoreText composition; no display-rate claim.
- Live installed UI: searched schedule, focused line 211 in Map, scrolled out/in,
  enlarged text, dragged vertically and horizontally, and exported a PNG.
- Fixed drag handling to derive movement from pointer locations.
- Final evidence: evidence/source-tiles-final/; app and zip both refreshed.
