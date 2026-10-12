# Authored Studio snapshot — 2026-10-12

Captured from place `127535941224851` before the separately authorized integration sync. This is a recovery/versioning snapshot, not an automatic runtime map builder or a Rojo deployment target.

- `authored-place.rbxm`: native engine serialization of 3,114 authored roots across Workspace, ReplicatedStorage, ReplicatedFirst, ServerScriptService, ServerStorage, StarterPlayer, StarterGui, StarterPack, Lighting, SoundService, Teams and Chat. Includes models, map geometry, native UI and scripts embedded in assets.
- `authored-terrain.rbxm`: complete sparse TerrainRegion captured with `Terrain:CopyRegion(Terrain.MaxExtents)`. Restore corner is `(-32000, -32000, -32000)` in cell coordinates. No terrain was cleared or pasted during capture.
- `editor-sources.json`: all 690 readable script editor sources, Base64 encoded to preserve original bytes, including two legacy asset scripts containing non-UTF-8 comments. Open editor buffers are captured even if not yet committed to the Source property.
- `manifest.json`: root order/parent paths, original script count, UTC timestamp, terrain information, archive sizes and SHA-256 hashes. The non-archivable Rojo session lock and editor camera are excluded.

The 173 scripts under source-mapped services were also exported into `src/` before integrating local changes. Workspace/ServerStorage embedded scripts stay with their native objects in this snapshot; no standalone duplicates are deployed into those objects.

Native roots are intentionally unparented on deserialization. A recovery must place each root under the matching service according to `manifest.json`, and must be performed in a separate recovery place or explicitly approved session. Do not import this snapshot over a collaborator's active map. Native deserialization can use the official SerializationService; script buffers can be decoded with EncodingService or a standard Base64 decoder.

The legacy `MapData` / `DevMapTool` recovery pipeline remains intact. Its model-only placement serializer cannot faithfully represent the current map's many loose MeshParts; this complete native snapshot preserves those authored objects without replacing that pipeline with invalid placement data.
