# AGENTS.md

## Project

This is a Roblox multiplayer game written in Luau.
Stack: Roblox Studio, Rojo, Rokit, GitHub, Codex. Git is the source of truth.

---

## Core Rules

### 1. Preserve existing architecture

- Inspect relevant modules before coding.
- Reuse systems, don't rewrite working code without a clear reason.
- Prefer small, focused changes.

### 2. Server authority

- The server is absolutely authoritative.
- Never trust the client for: currency, purchases, inventory, damage, rewards, progression, or permissions.
- Client input (RemoteEvents/RemoteFunctions) MUST be strictly validated by the server.

### 3. Code organization

- `src/ServerScriptService/` - server systems
- `src/ReplicatedStorage/Shared/` - shared modules
- `src/ReplicatedStorage/Remotes/` - networking objects
- `src/StarterPlayer/StarterPlayerScripts/` - client systems
- `src/StarterGui/` - UI
- `assets/` - source and generated game assets
- `docs/` - project documentation
- `tests/` - tests and test utilities
- Keep modules focused (SRP). Prefer ModuleScripts over monolithic scripts.

### 4. Luau

- Use strict typed Luau where practical.
- Prefer explicit interfaces, early validation, and predictable data structures.
- Avoid magic numbers and global state.
- Comments should explain **why**, not what.

### 5. Networking

- Treat all remote calls as malicious untrusted input.
- Always validate: argument types, ranges, player permissions, game state, and enforce server-side cooldowns.

### 6. Data & Configuration

- Game configuration must be data-driven.
- Prefer centralized configuration modules over hardcoded values.

### 7. Performance & Memory

- **Memory Leaks:** Always clean up event connections (use Maid, Janitor, or explicitly disconnect) when instances are destroyed.
- Avoid unnecessary loops, excessive polling, expensive per-frame work, and high RemoteEvent traffic.
- Prefer event-driven systems.

### 8. Assets

- Don't duplicate assets. Use existing reusable assets or generators.
- Blender/Python asset generation belongs in the pipeline, not gameplay code.

### 9. Documentation

- Document architectural decisions in `docs/` and update them when making changes.

### 10. Git Workflow

- Never commit directly to `main`.
- Use consistent branch and commit naming:
  - `feat/<name>` -> `feat: <description>`
  - `fix/<name>` -> `fix: <description>`
  - `refactor/<name>` -> `refactor: <description>`
  - `chore/<name>` -> `chore: <description>`
- Keep commits focused. Avoid giant commits.

### 11. Pull Requests

- PRs are required for `main`.
- Verify builds, test gameplay, and review your diff before opening a PR.

### 12. Do not destroy work

- Never delete systems without checking dependencies or overwrite unrelated files just to "clean up".

### 13. Secrets

- Never commit API keys, tokens, passwords, or `.env` files.

### 14. Agent behavior

- Check the repo, read docs, and identify systems BEFORE writing code.
- Do not invent non-existent APIs, files, or modules.
- Make the smallest reasonable change.

### 15. Product decisions

- Implement documented product decisions.
- Do NOT silently change core loops, economy, progression, or architecture. Flag missing product decisions instead of making them up.

---

## Definition of Done

A task is complete when:

1. The implementation works and is tested.
2. No obvious errors/memory leaks remain.
3. The diff contains ONLY relevant changes.
4. Documentation is updated.
