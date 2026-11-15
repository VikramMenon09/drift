# Drift

Near-black live wallpapers for macOS. Nine Metal shader designs (Silk, Rings, Dots, Honeycomb, Waves, Facets, Orbits, Tunnel and Cubes) with a menu bar picker. Each one draws at 30 fps and pauses whenever the desktop is covered.

## Try it in the browser

**[drift-green-zeta.vercel.app](https://drift-green-zeta.vercel.app)**

All nine designs run in any browser with WebGL2. Switch with the picker, the arrow keys or 1–9. Space pauses, F goes fullscreen and H hides the controls. Link to a single design with its name, e.g. [`#tunnel`](https://drift-green-zeta.vercel.app/#tunnel).

The web version lives in [`web/`](web). It's a plain static page with no build step. [`web/shaders.js`](web/shaders.js) holds GLSL ports of the Metal shaders in `main.swift`, with the same math, palette and speed. At the same time and resolution they match the app's `--snapshot` output to within 1/255 per pixel. If your system asks for reduced motion, the page starts paused.

## Build the Mac app

```sh
./build.sh          # writes Drift.app next to this folder
```

Needs macOS 13+ and the Xcode command line tools. Pick a design from the moon icon in the menu bar.
