# RAD DRIFT

A fast top-down arena roguelite — **written from scratch in Zig, no standard library, no
allocator, no engine, no assets** — compiled to a single WebAssembly module and played in the
browser on a 480×270 software-rendered framebuffer.

**▶ Play: https://moai-heads.github.io/raddrift/**

## The game

Auto-fire at the nearest hostile, kite the swarm, and dash *through* enemies to shred them.
Collect shards, level up, stack perks. Waves escalate every 22 s; everey third wave drops a
ring-firing **OVERSEER** boss.

- **WASD** move · **SPACE** dash (i-frames + contact damage) · **1/2/3** pick a perk · **R** retry
- Weapon heat system — hold the trigger too long and you overheat
- 30+ stackable upgrades: multishot, pierce, crit, homing, lifesteal, thorns, explosions,
  chain-reaction bullets, out-of-combat regen, and more
- Combo multiplier, screenshake, hitstop, crits, gore bursts — all hand-rolled
- Procedural WebAudio SFX + a pulsing bassline that intensifies as the run drags on

## Why it's interesting (engineering)

Everything is `wasm32-freestanding` Zig with **zero imports** — the module only exports
`memory` and a handful of functions. The host JS does nothing but pump input, blit the RGBA
framebuffer into an `ImageData`, and synth audio.

- `src/font.zig` — a 5×7 bitmap font baked as Zig data; text is drawn glyph-by-glyph
- `src/main.zig` — one ~1.5k-line file: fixed-size entity pools (bullets / enemies / particles /
  crystals), a xorshift RNG, the whole upgrade table, the renderer, and the game loop
- Deterministic-ish simulation driven by exported `frame(dt_ms)`; the browser owns the clock
- One file, one build command, ~1 MB of wasm

## Build

```sh
./build.sh          # zig build-exe src/main.zig -target wasm32-freestanding -> web/raddrift.wasm
```

Requires **Zig 0.14.x**. Then serve `web/` over HTTP (the page fetches the wasm):

```sh
python3 -m http.server -d web 8080   # http://localhost:8080
```

## Test / verify

The sim is fully driveable headlessly — no browser needed to play it:

```sh
node tools/smoke.js     # boot, render a frame, sanity-check the framebuffer
node tools/soak3.js     # long run: title->play->cards->death->retry, watch for traps
node tools/bot2.js      # a threat-avoiding bot, measures natural survival time
node tools/drive.js     # drives the real page in headless Chromium, screenshots it
```

## Deploy

```sh
./deploy.sh "commit message"   # pushes main + rebuilds the gh-pages branch from web/
```

## Layout

```
src/main.zig     the game
src/font.zig     5x7 bitmap font
web/index.html   page shell (CRT scanlines, vignette, controls)
web/game.js      host: input, blit loop, procedural audio
tools/           headless test + CI bots
```
