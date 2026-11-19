# ProceduralWorlds – Roblox terrain framework

Seeded, biome-driven terrain that streams around players and saves to DataStore.

## Install

**Rojo:** `rojo serve` using `default.project.json`.

**Manually in Studio:**
1. In `ServerStorage`, make a **ModuleScript** named `WorldFramework` and paste `init.luau` into it.
2. Add these child ModuleScripts under it with the matching names/contents:
   `Config`, `Biomes`, `Noise`, `TerrainGenerator`, `Decorator`, `ChunkManager`, `WorldStore`.
3. In `ServerScriptService`, add a **Script** with the contents of `WorldMain.server.luau`.
4. Game Settings → Security → enable **Studio Access to API Services** (to test saving in Studio).

## How it works

- **Generation** is a pure function of the seed: continentalness decides ocean vs land; temperature +
  moisture noise place biomes on a climate plane; heights are blended between nearby biomes (so borders
  are smooth); ridged noise makes mountains; 3D "spaghetti" noise carves caves; beaches, sea level
  water, snow caps and underwater materials are automatic.
- **Saving** stores the seed + world meta, and per-chunk *edits* (terrain carve/fill, removed
  trees). Terrain is never saved wholesale, so saves are tiny and chunk loads cost no DataStore
  requests unless that chunk was edited. Unloaded chunks are erased and regenerated on demand.
- **Decorations** are deterministic per chunk with stable IDs; use your own models by putting
  Models named after the decoration `Type` in `ServerStorage.WorldAssets`.

## API

```lua
local world = World.new({ WorldId = "Player_" .. userId, ViewDistance = 6 })
world:Load(); world:Start()

world:ModifyTerrain(pos, radius, Enum.Material.Air)  -- persisted dig/build
world:RemoveDecoration(instance)                     -- persisted
world:GetBiomeAt(pos)                                -- name, {Temperature, Moisture, Height}
world:FindLandNear(x, z)                             -- Vector3 on dry land
world:PreloadAround(pos, radiusChunks)               -- yields until loaded
world:SetMeta(k, v) / world:GetMeta(k)               -- custom saved data
world:RegisterDecoration("Lamp", function(rng, scale) return model end)
world:Save(); world:Destroy()
world.ChunkLoaded:Connect(function(cx, cz) end)
```

## Customizing biomes
Edit `Biomes.luau`. Add a table with `Temperature`/`Moisture` (0–1), `Base`/`Amplitude` height,
materials, and a weighted `Decorations` list. Pass `Biomes = {...}` to `World.new` to override per-world.

## Caveats
- One server should own a given `WorldId` at a time (private server / per-player world / single server).
- Changing noise settings or biome heights on an existing save shifts terrain under old edits; bump
  `GeneratorVersion` so you notice. Seed/ChunkSize/ChunkHeight/SeaLevel are locked to the save.
- Edits per chunk are capped (`MaxEditsPerChunk`, default 500); oldest are dropped beyond that.
