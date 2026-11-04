# ObbyRace

A Roblox obby (obstacle course) racing game. Code is written in Luau and synced into Roblox Studio with Rojo.

## Tools

- **Rojo** syncs `src/` into Studio. Version is pinned in `rokit.toml`; run `rokit install` if `rojo` is missing.
- **Git** for version control. Commit code only; place files are ignored (see `.gitignore`).

## Scripts go in files, not Studio

- ALWAYS create and edit scripts as files in `src/` — Rojo syncs them into Studio.
- NEVER create or edit Script, LocalScript or ModuleScript instances directly in Studio through the Studio connection. Those changes aren't saved to Git and Rojo may overwrite them.
- The Studio connection is fine for reading the game tree, checking output/errors, playtesting, and building parts/maps/UI.

## Commands

- `rojo serve` — start live sync (then click Connect in the Rojo plugin in Studio)
- `rojo build -o ObbyRace.rbxlx` — build a place file
- `rojo sourcemap -o sourcemap.json` — regenerate the sourcemap for Luau LSP

## Project layout

Mapping is defined in `default.project.json`:

- `src/server/` → `ServerScriptService.Server` — server-only logic (checkpoints, race timing, data saving)
- `src/client/` → `StarterPlayer.StarterPlayerScripts.Client` — client logic (UI, input, effects)
- `src/shared/` → `ReplicatedStorage.Shared` — modules used by both server and client

## File naming (Rojo conventions)

- `Name.server.luau` → Script
- `Name.client.luau` → LocalScript
- `Name.luau` → ModuleScript
- A folder containing `init.luau` (or `init.server.luau` / `init.client.luau`) becomes that script, with the folder's other files as its children
- `.rbxm` / `.rbxmx` files become model instances

## Code style

- Use Luau with `--!strict` at the top of new files where practical, and add type annotations.
- Get services with `game:GetService("ServiceName")`, declared at the top of the file.
- Use `task.wait`, `task.spawn`, `task.delay` — never the deprecated `wait`, `spawn`, `delay`.
- Prefer ModuleScripts in `src/shared/` over duplicating code between server and client.
- Use PascalCase for modules and services, camelCase for local variables and functions.

## Roblox rules to respect

- **Never trust the client.** Validate everything the server receives through RemoteEvents/RemoteFunctions (e.g. a player claiming they reached a checkpoint must be checked server-side by position/order).
- Anything in `src/client/` or `src/shared/` is visible to exploiters — keep secrets and authoritative logic in `src/server/`.
- Wrap DataStore calls in `pcall` and handle failures; don't call DataStores in tight loops.
- Disconnect connections and clean up when players leave to avoid memory leaks.

## Things not in this repo

The map, obstacles, parts and most UI are built in Roblox Studio and are **not** in `src/`. They're backed up via Roblox's place version history. When code references workspace objects (e.g. `workspace.Checkpoints`), assume they exist in the place file and don't try to create them in code unless asked.

## Working agreements

- Don't edit `ObbyRace.rbxlx`, `sourcemap.json`, or `.lock` files.
- Don't change `default.project.json` mappings without asking.
- Keep changes small and explain where a new script will appear in Studio.