# Project instructions

- RAD DRIFT: a no-libc Zig/WASM arena roguelite.
- Keep `src/main.zig` free of std/allocator imports — freestanding only.
- **Commit after every completed change**, with concise messages (`feat: …`, `fix: …`).
- Keep `PLAN.md` current as the project changes.
- Run `./build.sh` and `node tools/soak3.js` before pushing gameplay changes.
- Keep generated artifacts (wasm, ppm, png) out of `main`; they belong on `gh-pages` only.
- Do not modify the workspace-level `/root/AGENTS.md` from this project.
