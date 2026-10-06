# Installed source-tile verification — 2026-09-13

Application: `/Users/kelly/Applications/Kernel Atlas.app`

Confirmed in the native installed app using computer UI control:

1. Select Map, search `schedule`, select `schedule()` at `kernel/sched.c:211`.
2. Focus selected file. Actual highlighted definition and following syntax-colored
   source appear on the map, with original line numbers.
3. Scroll out and in over the code. Text scales around the pointer.
4. Drag up to bring further source lines into view. Increase zoom twice and drag
   right/down to reposition line 211 at a larger readable size.
5. Export through the app's native Save dialog to `source-live-map.png`.
6. Leave the app open on this Map/source view.

The native verification receipt contains 25 passing checks. Built and installed
executables have matching SHA-256:
`a7c02dd4eb2f0cec74b96c527f9d6d595490aa9f9d3d52a2836ff09591a79899`.

Refreshed archive `dist/Kernel-Atlas-Mac.zip` SHA-256:
`10732aa4d17c9ba5deafd3a9e896eb53334a0c76a2e78fbc32c9bf1eb1c25e53`.

Ad-hoc signature verified with `codesign --verify --deep --strict`.
No claim of notarization or guaranteed 120 Hz.
