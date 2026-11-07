# Steampunk Valley: Game Design Document

Nov 2, 2026 · @Marc

## Overview

Steampunk Valley is a first-person 3D survival and settlement-building game: a refugee of the fallen Gilded Empire builds a new home in a hidden valley, and every bit of steam power they harness draws the Hollows closer.

- **Genre:** survival, crafting, settlement building, base defense
- **Inspiration:** Medieval Dynasty, without the dynasty system, in a steampunk setting
- **Engine:** Godot 4.7, GDScript, built with help from Claude in VS Code

**Pillars**

1. **Build from nothing.** Start with scrap and sticks; end with a steam-powered settlement.
2. **Progress is risk.** Heat, smoke, and running machinery attract the Hollows, so every upgrade is a trade-off.
3. **A valley worth exploring.** Real-world terrain and ruins that slowly reveal what happened to the Empire.

## Story and setting

The Gilded Empire fell when its constructs stopped obeying; the player is an ordinary refugee who flees to a forgotten valley to start over.

**The Gilded Empire.** An empire of steam and clockwork. Its greatest achievement was the constructs, mechanical soldiers and laborers controlled from a great engine in the capital. Then something went wrong. The constructs turned, the capital fell, and the Empire collapsed in a single season.

**The Hollows.** The rogue constructs that now roam the wilds. They are drawn to heat, smoke, and running machinery.

**The player.** Just a refugee: no special past, no hidden connection to the constructs. Someone who survived the fall and needs a place to live. They reach the valley when the refugee airship carrying them crashes there. The wreck is their first shelter, their first source of scrap, and their first clue, since its log may say what brought it down. The game begins with a falling airship and ends with one the player builds.

**The valley.** A forgotten outpost on the edge of the old Empire, with a ruined airship dock, an abandoned steam town, and rusting machinery in the hills. Quiet, hidden, and a place to begin again.

**How the story unfolds**

- Journals and logs found in the outpost ruins
- Schematics that reveal what the constructs were built for
- Messages from passing airships about the wider world

**Endgame.** Build an airship, fly to the fallen capital, learn what really happened, and perhaps shut down whatever still drives the Hollows.

## Core gameplay loop

Each pass around the loop opens something the player couldn't do before, and each one makes the settlement louder and warmer for the Hollows to find.

&#91;embedded content: core gameplay loop · 6 steps\]

Gathering feeds crafting and building; a growing settlement unlocks new tech, which sends the player further out to find tougher resources.

## Progression

Four eras take the player from scrap to the sky, and each era's technology also raises the Hollows' attention.

| Era | What the player builds | Key resources | Main threat |
| --- | --- | --- | --- |
| 1. Scrap and Survival | Stone tools, campfire, rough shelter | Stone, plant fiber, sticks, wood, scrap, berries | Cold, hunger, wolves |
| 2. The Forge | Smelter, forge, workshop, bronze tools | Copper and tin, smelted into bronze; zinc for brass (proposed) | Lone Hollow scouts drawn by forge smoke |
| 3. Steam Power | Sawmill, water wheel, steam pump, steam shovel, walls and steam defenses, clockwork helpers | Iron and coal from underground, steel (proposed), gears, springs, copper plating from Hollows | Hollow raiding parties |
| 4. The Sky | Restored airship dock, trade with passing airships, own airship, clockwork guardians | Aether from capped vents, aluminum for airship frames, construct cores, trade goods | A major Hollow assault drawn by the dock's engines |

**How technology unlocks.** Two routes, mixed:

- **By doing:** chopping, mining, and crafting teach the basics (Medieval Dynasty style).
- **By discovering:** schematics found in ruins, and Hollow parts studied at the workshop, unlock the advanced tech.

**Underground resources.** Iron and coal don't sit on the surface. The player has to craft a prospecting tool to find deposits (ideas: a dowsing rod early, then a brass prospector's scope or seismic thumper), then dig or drill to reach them.

**A building for each tier.** Every tier adds its own production buildings, for example a smelter and forge for bronze, a blast furnace for iron and steel, an aether extractor, and an airship yard.

**Aluminum (proposed lore).** As in the real 1800s, aluminum is rarer than gold because refining it takes enormous power. Aether-powered refining is what finally makes it possible, which ties the last tier together. It is the lightweight metal for airship building.

## Threats

Early danger comes from the land; later danger comes from the Hollows, and the player's own progress is what calls them.

- **Survival pressure:** hunger and warmth meters (warmth drains faster at night). Planned: seasons with a harsh winter that needs steam heat, and tools that wear out.
- **Wolves:** the first hostile wildlife, in era 1.
- **The Hollows:** drawn to heat, smoke, and running machinery. A campfire barely registers; a forge brings scouts; boilers bring raiding parties; the airship dock brings a major assault.
- **Loot:** defeated Hollows drop gears, copper plating, springs, and eventually construct cores, which feed the tech tree.

**Design rule:** every upgrade is a choice between more power and staying under the radar.

## Combat and magitek

The player fights with a mix of melee, ranged weapons, firearms, and magitek, and the louder, hotter options draw more Hollows.

| Style | Examples | Strength | Cost |
| --- | --- | --- | --- |
| Melee | Wrench, cleaver, steam hammer | Needs no ammo, quiet | Close range is risky against big Hollows |
| Ranged | Bow, crossbow, bolt thrower | Silent | Slower, and ammo must be crafted |
| Firearms | Steam pistol, rifle, scattergun | High damage | Loud and hot, so it attracts Hollows; scarce ammo |
| Magitek | Aether gauntlet (lightning), ward lantern, charged blades | Powerful; can stun or disable Hollows | Runs on aether; its glow draws Hollows most of all |

**Aether.** The golden energy that gave the Gilded Empire its name. It powered the great control engine and every construct core, and whatever went wrong with it is what turned the constructs into Hollows. Aether rises from vents in the ground. To collect it, the player caps a vent by placing an extractor building on top of it, so vents are fixed points on the map worth finding, claiming, and defending.

## Settlement and defense

The player starts out doing everything alone and gradually becomes the leader of a working settlement that has to defend itself.

- **Settlers:** other refugees arrive once there is housing, food, and warmth.
- **Jobs:** settlers are assigned work such as woodcutter, miner, stoker, or farmer, and the settlement produces on its own.
- **Defense:** walls, watchtowers, and steam-powered defenses against Hollow raids.
- **Clockwork guardians:** late game, reprogrammed construct cores become defenders, turning the Empire's weapons against its ruins.
- **Terraforming:** a craftable, coal-fuelled steam shovel raises, lowers, and flattens ground for foundations, ponds, and channels from the river. Height-based only, so no caves or tunnels. It needs a save system so changes persist.

## Building system

The player builds freely rather than following fixed plans: the goal is closer to RuneScape: Dragonwilds than to Medieval Dynasty's set build stages.

- **Snap pieces (proposed approach):** foundations, walls, floors, roof sections, stairs, and doors that snap to a grid and to each other. Players design their own buildings while the number of pieces to build and test stays manageable.
- **Production buildings:** each tier's workstations (smelter, forge, extractor) are placed as ready-made objects inside or beside the player's own structures.
- **Build it early:** this is the hardest system and the one that matters most, so a small prototype (place a wall, snap a second to it) comes before content.

## World and look

The valley is built from real-world elevation data and is heading toward a realistic natural look, with steampunk ruins layered on top.

- **Terrain:** a heightmap of rolling hills in the English Midlands (36 to 226 m real elevation), built in chunks. Currently 1500 m across with the hills exaggerated. The rest of the heightmap is room to expand, and airship travel can open new regions later.
- **Water:** a single water level fills the low ground, forming the river and lake.
- **Visual target:** a realistic forest-and-stream look like the reference screenshot (rocky slopes, ferns, deer). Lighting, fog, shaders, and procedural grass come first; real art assets (Poly Haven, ambientCG, asset packs) replace placeholders in a later beauty pass.
- **Asset credits:** every third-party asset must be listed in `CREDITS.md` (name, author, source, license, where it is used, and file path). `CREDITS.md` will feed an in-game credits screen later.
- **Places to discover:** the ruined airship dock, an abandoned workshop, and rusting machinery in the hills.
- **The castle:** a ruined Gilded Empire fortress retrofitted with steam machinery (gears, pipes and a great clock on its tower), standing in the saddle between two peaks and overlooking the road. The gatehouse is the enterable part: the player walks through its breach into a small courtyard. Not yet placed in the world; the model in the project so far is the whole castle, entered through a breach in its west wall and the clock tower's door, and a separate gatehouse model is still to come.
- **Map shape and border:** the playable area doesn't need to be square. Natural borders such as steep hills, cliffs, a gorge, or fog mark the edge, with an invisible wall behind them as a backstop. Beyond the border, low-detail terrain with no foliage or collision keeps the world looking continuous.
- **World map:** an overhead render of the terrain, styled like an old hand-drawn chart, with markers for the player and discovered vents (proposed).

## Regions

The world grows one region at a time: each region is its own open map, and airships carry the player between them. Names beyond the Valley are placeholders.

| Region | Character | Key resources | Hollow threat |
| --- | --- | --- | --- |
| The Valley (start) | Rolling hills, river and lake, crash site, outpost ruins | Stone, fiber, sticks, wood, scrap, copper, tin; iron and coal underground; aether vents | Scouts and small raids |
| Rust Wastes (idea) | Industrial ruins and old factories | Machine parts, oil, rare metals | Large working Hollows |
| Frost Highlands (idea) | Cold peaks where steam heat is survival | Aether crystals, furs | Hollows that hunt heat |
| The Fallen Capital (endgame) | The Empire's ruined heart and the great engine | Aether, the Empire's secrets | Everything |

Separate maps keep each region fast to load and build; seamless travel between regions can come later if wanted.

## World tools

The valley is built by a script from a real-world heightmap, then shaped and dressed by hand with editor tools. Everything made by hand is saved in `world/world.tscn` (or, for ground paint, in its own file), so a rebuild always gives the same result. Nothing rebuilds while the mouse is held down: the ground updates once, when you let go.

**How a rebuild fits together, in order**

1. Heights come from the heightmap, smoothed. Gullies are carved into the tall peaks where water would drain, leaving ridges between them, fading in from 120 m (the Valley's *Tall peaks* settings), so nothing lower changes.
2. Terrain modifiers reshape the ground, in scene order (so a Flatten placed before a trail is in place when the trail runs into it).
3. Sculpt Brush shaping is added, just before the first trail.
4. Trails cut their walkable surface into the ground, and note where their gravel and edge grass go.
5. The crash site and anything in the `snap_to_ground` group (including every object placed with the Object Painter) are set down on the finished ground.
6. Trees, resources and boulders are scattered. No trees are scattered above the tree line (about 125 m). They keep off trails, the crash site, Clear Zones, spots rubbed out with the Object Painter's eraser, and the room around hand-placed objects.
7. Grass and ferns grow near the camera, with tufts along trail edges.
8. The forest floor is worked out from where all the trees stand, and the ground material blends everything: automatic coloring first, then trails, then Texture Brush paint on top.

**World Tools panel** (a tab beside the Inspector; Project > Tools > Show World Tools brings it back)

- *Add:* buttons for a Lower, Raise, Flatten, Smooth or Squash modifier, a Path (trail) or a Clear Zone. Press one, then click the ground where it should go (Esc or right-click cancels). Each goes under `TerrainEdits` in the world scene, in its own group, at ground height. A new Raise/Lower has no effect until it's moved. A new Flatten starts with Falloff 0.7, and levels its circle to the height clicked straight away.
- *Paint:* the Object Painter, Texture Brush and Sculpt Brush toggles, each with its own settings below.
- *View:* Show Slope View (green = walkable, yellow = near the limit, red = too steep), Show Modifier Markers, and Rebuild Terrain.
- *In the world:* a list of every modifier, trail and clear zone. Click one to select it and fly the view to it; the bin icon deletes it.

**Terrain modifiers** reshape the ground inside a circle, and the marker's 3D position is the control point: move it with Godot's move gizmo on any axis and the terrain follows, live for the chunks it touches, with the full rebuild (trails, collision, and everything on the ground) when it stops. X and Z say where it acts. *Flatten* levels the ground to the marker's height (or with *Level To Ground*, off by default, to the average of what's there). *Raise/Lower* (one mode) moves the ground by how far the marker is above or below it at its middle, keeping the ground's own bumps: at full *Strength* the middle reaches the marker; lower Strength goes only part of the way. For *Smooth* and *Squash* only X and Z matter; their amount is set in the Inspector. *Radius*, *Strength* and *Falloff* (how soft the edge is) are in the Inspector too, and dragging the outer ring changes the radius (Shift for fine changes). Modifiers are never snapped to the ground, so a marker stays exactly where it's put.

**Trails** (TerrainPath) carve a walkable path along a curve, never steeper than *Max Slope*, with *Width*, *Edge Blend* (how far the sides fade into the hillside), *Smoothness* and *Cross Slope* (flat across, or tilting with the hill). The surface is gravel (*Dirt Texture* on), fading out over *Texture Blend Width* with an edge as ragged as *Edge Noise*; *Edge Grass* grows tufts along the edges and a few patches on the trail. *Clear Objects* and *Clear Margin* keep trees, rocks and plants off it. With a trail selected (Terrain Path Tools): drag a point to move it, drag the trail to bend it, Ctrl + click to add a point at the end (Ctrl + Shift + click at the start), Alt + click a point to delete it, Shift for fine moves, right-click to cancel.

**Clear Zones** keep a circle clear of scattered trees, resources, boulders and (optionally) plants, without changing the ground.

**Object Painter** places trees, rocks, bushes and landmarks. Its palette is built from the scenes in `assets/`: anything under a folder named `trees`, `rocks`, `bushes` or `landmarks` appears in that category (trees must be `.tscn` scenes with the choppable tree script; the rest can be plain models, and a model with a scene of the same name beside it is listed once, as the scene), so new assets show up without code changes. Pick one, or Ctrl + click several to paint a mix. Click to place one exactly; drag to paint many over *Brush Radius* at about *Density* per 100 square meters; Alt + click or drag to erase, which also rubs out the valley's own scattered trees, rocks and resources so they don't come back on rebuild. Drag a placed object to move it along the ground (Shift for fine moves). Each kind follows its own rules: trees stand upright with their roots sunk in and stay choppable; rocks tilt to the slope, sink 20 to 40% into the ground and vary in size and turn; small stones come in clusters; bushes lean a little with the slope; large rock outcrops stand upright, sink 10 to 20% below the lowest ground under them, and vary in turn and size; landmarks go down one at a time by clicking, upright on the ground, and are turned with the rotate tool. A scene can set these rules itself in its root node's metadata (`placement_upright`, `placement_sink`, `placement_size`, `placement_clear`). Outcrops and landmarks keep the valley's scattered trees, rocks, resources and plants out of a circle around them, rebuilding when one is placed, moved or removed. Landmarks with a built-in base, like the castle, need a Flatten modifier under them, or the terrain pokes through their ground. Placed objects live under `TerrainEdits/Objects` and stay snapped to the ground through rebuilds. The pickup models' folders (`rocks/stone`, `sticks`, `bushes/plant_fiber`) are kept out of the palette, since those are gathered, not decoration. Objects from folders kept out of git (paid packs) are marked *local*.

**Texture Brush** paints ground materials over the automatic coloring: grass, dirt, and every texture set in `assets/textures/`, picked from a grid of small pictures of each set's Color image, with *Brush Radius*, *Strength* and *Falloff*. Alt erases back to the automatic coloring. Materials blend by height using their Displacement maps: stones show through first, and grass fills the low spots. Up to twelve materials can be painted in a world. The painting is saved to `world/terrain_paint.res` after every stroke and survives rebuilds; each stroke is one Ctrl+Z step.

**Sculpt Brush** shapes the ground by painting on it, and is the easy way to shape land; terrain modifiers still work for anyone who prefers them. Modes: *Raise*, *Lower* and *Smooth* work for as long as the mouse is held; *Flatten* pulls the ground toward a height sampled with Ctrl + click (shown as a label and a faint flat disc at that level; with nothing sampled, it levels to where the stroke starts); *Ramp* makes a smooth slope from where the mouse is pressed to where it's let go, as wide as the brush (Strength doesn't apply). Alt + drag rubs sculpting out. Settings: *Brush Radius*, *Strength*, *Falloff*. The terrain is a 2 m grid, so that's the finest detail it can hold. While painting, only the affected chunks' meshes update, with no collision; on release, the trails recompute and everything standing on the ground follows it. Shaping is saved to `world/terrain_sculpt.res` after every stroke and survives rebuilds; each stroke is one Ctrl+Z step. It goes on after modifiers but before trails, so trails cut through sculpted ground. (A modifier listed after a trail in the scene still applies after it, as it always has.)

**Ground materials** (`world/terrain.gdshader`): the automatic coloring is grass and dirt patches on gentle ground, mossy forest floor under trees, wet mud at the shore, churned mud and puddles at the crash site, and on the mountains a mix of rocks. Rock rises through the grass from about 30 degrees, in broken outcrops (a pattern shifts where it begins, and height blending brings the tallest stones through first), until it covers the ground by about 52 degrees. Within it: mossy rock on moderately steep slopes and those facing away from the sun, plain rock between, sheer cliff rock in swathes across the steepest faces, and scree at the foot of steep slopes and down gullies (found from the heights around each spot). Broad lighter and darker swathes, streaks down the faces, cooler and warmer stone, and the cliff rock's own pattern blown up big keep mountains from reading as one even tone from far away. The rock darkens in the ground's real hollows and lightens where it bulges, turns pale in soft patches from about 105 m up, and green follows where water would really drain, using a flow map the Valley bakes from the terrain on each rebuild, so it runs down the actual gullies. The material's *Mountain veins* settings tune these (green colors and amount, hollow shading, the pale rock's color and height). Patterns on the rock must not run in a direction: stretched along a slope, they show up as stripes across every mountain. Rock is projected from three sides so cliffs don't stretch.

**Texture sets** live in `assets/textures/`, one per `*_Color` image, with its NormalGL, Roughness, Displacement and (optionally) AmbientOcclusion maps beside it, named alike. A new set dropped in there shows up in the Texture Brush by itself and is used by the ground from the next rebuild; for the fastest loading, import its maps as VRAM Compressed at 2048 (NormalGL as a normal map), like the others. The Valley's *Ground materials* settings pick which set does each job (forest floor, gravel and sandy path, light and dark soil, plain, mossy and cliff rock, scree), and the material's *Mountains* settings tune where they go. The sets repeat every 2.5 to 6 m, with a second, larger copy blended in to hide the repeats.

## Current build status

The first-era survival loop is playable: walk, gather, chop, eat, build a fire, and survive the night.

**Working**

- First-person movement, mouse look, and jumping
- Day/night cycle with warm sunsets and dark nights
- Real-world heightmap terrain in chunks, with water filling the low ground
- Visual pass: slope-based ground coloring, grass, rocks, improved trees, water shader, haze
- Gathering sticks, stone, plant fiber, scrap and berries by hand with E. Stone, sticks and plant fiber use Meshy models (`assets/rocks/stone/`, `assets/sticks/`, `assets/bushes/plant_fiber/`), each scattered with its own turn and size (85 to 115%), seated against the drawn ground so no edge floats, with a small box to gather by. The models are low-poly GLBs (`stone.glb`, `sticks.glb`, `plant_fiber.glb`, about 400 to 480 triangles each); their textures are capped by import settings at 1024 (stone, sticks) and 512 (plant fiber)
- Tree chopping with the axe in hand: 4 hits, the tree falls, a stump remains, +3 wood
- Hunger and warmth meters; eat berries with F
- Inventory screen on I with 20 slots, and a Crafting tab: a list of recipes, each one's details and have / need costs, and a Craft button. Each recipe is a resource file in `crafting/`, listed by itself, with a station field: "hand" for now, and `nearby_stations()` in `player/player.gd` is where a workbench or forge would add theirs
- Action bar: nine slots along the bottom, selected with 1-9 or the mouse wheel, showing the held item in front of the view. Crafted tools go into the inventory and are dragged onto the bar and back; items on the bar still count as owned. Each tool is a resource file in `tools/` (with its model), which the bar finds by itself. G drops the held tool on the ground and E picks it back up
- Stone tools: hammer (build menu), axe (chops trees), pickaxe (mines rocks and boulders for stone), knife (double plant fiber per harvest). Their models and textures are in `assets/tier_1_tools/` (one folder per tool), with a simple placeholder used if a model is ever missing. Each tool's file in `tools/` sets its model, size, and how it sits in the hand and on the ground; its material is `tools/<name>_material.tres`. The models are very detailed (over 500,000 triangles each) and will need reducing at some point
- Build menu on Tab while holding the hammer; each buildable is a resource file in `buildables/`, which the menu lists by itself
- Placing a building: a see-through preview on the ground, green or red (too steep, in water, or overlapping something); left-click places and pays, R rotates, right-click or Esc cancels
- Campfire: 3 wood, or 6 sticks and 2 stone. Meshy model (`assets/buildables/campfire/`) of stones and logs; the flame and its light show only while it's lit
- Lean-to: 8 sticks, 4 wood, 6 plant fiber; unlocked by crafting the hammer. Meshy model (`assets/buildables/lean_to/`); only its two front posts and roof are solid, so you can walk under it. Look at the mat and press E to sleep: at night only, it fades to black and skips to just after sunrise, costs a quarter of your hunger, and you wake warm only if a lit campfire is within 5 m (otherwise cold)
- Unlocks: any buildable or recipe can start locked, and its file says what unlocks it (crafting, gathering or building something named). Unlocking shows "New blueprint: ...". Locked buildables show in the build menu as dark slots with a hint ("Craft a hammer to unlock"); locked recipes stay out of the Crafting tab. Unlocks aren't saved yet (there's no save system)

**Switched off until the iron tier**

The dowsing rod (item, recipe, pulse) and the buried iron and coal seams (markers and dig spots) are kept in `iron_tier/`. Setting `ENABLED` to true in `iron_tier/iron_tier.gd` brings them all back. While it's off, the game has no source of iron or coal.

**Known issues**

- Some rocks float or sit sideways on steep slopes
- Hills look domed and rocky; try a lower height scale for true rolling hills
- The near map edge ends in a cut-off wall

## Roadmap and open questions

Next comes filling the valley with things to find, then crafting and building, then the Hollows.

**Next up, in order**

1. More gatherables placed by the terrain script: stone, plant fiber, sticks, copper and tin ore, mushrooms, herbs (iron and coal move underground)
2. Places to discover: the ruined airship dock and an abandoned workshop
3. Wolves
4. Crafting and a snap-piece building prototype, with a flatten-ground tool
5. Save system
6. Seasons
7. Settlers and jobs
8. The Hollows, walls, and defenses
9. Airships: first a ship drifting across the sky, then trade at the dock

**Open questions**

- [x] How did the player reach the valley? A crashed refugee airship.
- [x] Combat style: a mix of melee, ranged, firearms, and magitek.
- [ ] What went wrong with the engine that controlled the constructs? Something went wrong with the aether; the details are still open.
- [ ] What brought the refugee airship down?
- [ ] Is the era 4 assault the game's final battle, or does that happen at the capital?
- [ ] Where does aluminum ore come from: the Valley or another region?
- [ ] Do Hollow cores still hold some aether, or do vents replace them entirely?
- [ ] What shape is the Valley's playable area, and what forms its border?
