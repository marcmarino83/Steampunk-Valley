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
- **Jobs:** settlers work at a workplace plot (woodcutter, miner, stoker, farmer). At the end of each day their output is calculated and added to the warehouse, so later in the game the player no longer has to grind for materials.
- **Defense:** walls, watchtowers, and steam-powered defenses against Hollow raids.
- **Clockwork guardians:** late game, reprogrammed construct cores become defenders, turning the Empire's weapons against its ruins.
- **Terraforming:** a craftable, coal-fuelled steam shovel raises, lowers, and flattens ground for foundations, ponds, and channels from the river. Height-based only, so no caves or tunnels. It needs a save system so changes persist.

## Building system

The player builds freely with Valheim-style snap pieces, and plots turn those structures into working buildings. Free building stays closer to RuneScape: Dragonwilds than to Medieval Dynasty's set build stages.

**Pieces**

- **Snap pieces:** foundations, walls, floors, roof sections, stairs and doors that snap to each other.
- **Round builds:** curved wall arcs (22.5° and 45°) that close into full circles, round tower kits (circular floors, cone roofs, spiral stairs), and 15° rotation steps with a hold-key for free rotation.
- **Not voxels:** Enshrouded-style smooth voxel building was ruled out as too big for a first project, and it would not fit the existing terrain.
- **Built so far (first version):** wooden pieces in the hammer's build menu, under tabs (Foundations, Floors, Walls, Roofs, Beams & Pillars, Stairs & Doors, Round, Other; Q and E change tab). Square pieces (2 m grid, 1 m half step): wood and stone foundations (solid blocks 3 m tall that go 2 m into the ground, stacking and snapping side by side; floors, walls and stairs snap onto their tops like onto floors), floor, wall (2.5 m high), doorway wall, door (E opens and closes it), window wall, 26° roof (rises 1 m over 2 m), stairs, and wood and stone pillars (on floor and foundation corners and edge middles, stacking; floors, walls and roofs sit on their tops, for platforms and porches; pillars only bump into other pillars). Triangles combine with the squares: a right triangle (half a square, long side 2.83 m) and a 45° triangle (two 2 m sides at 45°, short side 1.53 m, filling the gap between squares turned 45°, so squares and triangles make an octagon), each as a floor and a wood and stone foundation, with long (2.83 m) and short (1.53 m) walls for their odd sides. *Round* (one ring, radius 2.61 m, so a 45° arc spans 2 m and eight close a circle 5.2 m across): wood and stone round foundation wedges, curved walls (45° and 22.5°), round floor wedges and cone roof wedges (eighths), and 22.5° round floor and foundation wedges (sixteenths) to match the 22.5° walls. A round wedge's curved edge lies exactly under the curved walls' middle line. Every piece unlocks with the first planks. Pieces snap (dots show the snap points; while snapped, R turns the piece about the snap point in 90° steps, 45° for round and triangle pieces, and Alt + wheel in 15° steps, and the turn stays until a different piece is picked); otherwise they go wherever the crosshair is, on the ground or on other pieces, and may float: R turns 15°, Alt + wheel turns smoothly, Page Up / Page Down or Ctrl + wheel raise and lower in 0.25 m steps (0.05 m with Alt), kept for the next piece of the same kind until Backspace, and Shift skips snapping. Red only where a piece bumps into another piece, a tree or a rock (the ground is fine). Demolishing is a one-shot mode: with the hammer out, middle-click turns it on (any placement preview hides), the piece under the crosshair glows red, and left-click demolishes that one piece for a full refund, then it's back to normal (and to placing, if you were); right-click, Esc or middle-click again cancels. Holding X on a piece does the same directly (it glows red with a percentage while held; letting go early cancels). Nothing glows or gets removed otherwise. What won't fit in a full backpack is left in a bundle on the ground, picked up with E. Under a roof counts as shelter; a closed room (floor, walls, roof, door shut) stops the cold entirely, round rooms included. Floors and foundations keep the grass out. No structural support yet. Shapes and snap rules: `building/pieces/piece_shapes.gd`; each piece is a `PieceBuildable` in `buildables/structure/` or `buildables/round/`, and can show a real model instead of the plain shape (`model_scene`). For plots: every piece has an id and an owner plot (empty for now), listed in the `PieceRegistry`, which also saves them.
- **The small kit (Valheim-style):** a 1×1 m floor; 1 m walls, half-height walls (2 m and 1 m wide, 1.25 m high) and a 1×1 m quarter wall, which snap to the 1 m points on floor edges and wall tops; gables (wall triangles) for the 26° and 45° roofs, standing on the wall under a roof end; a 45° roof, and for each pitch an inner corner (valley), outer corner (hip) and ridge cap, which snap onto roofs of their own pitch; beams (1 m, 2 m, and diagonals at 26° and 45°) and poles (1 m, 2 m), which snap end to end, to floor corners and edge middles, to wall-top corners and middles, along wall tops, and to each other; a 2 m ladder (hold W while facing it to climb); railings (2 m, 1 m) and a 2 m fence that chain end to end. Pillars, poles, beams and ladders only bump into each other.

**Plots**

- **Chosen from a list** of available building types (house, forge, storehouse). Each type has requirements, such as workplace items or housing furniture, shown as a checklist. The building works only when they are met; extra decoration is up to the player.
- **Adjustable at any time:** plots can be resized and moved whenever the player likes. The building re-checks its requirements after every change and stops working (NPCs included) if something required ends up outside.
- **Overlap allowed:** plots can overlap so buildings can connect. Placement fails only when pieces collide.
- **Ownership:** every piece belongs to the plot it was placed in, even inside an overlap, and only its own pieces count toward its requirements.
- **Moving a building** takes only its own pieces. A gap left in a connected building is rebuilt by hand. (Proposed: the new spot is checked for slope, and the ground is flattened or the move is blocked.)
- **Shrinking a plot:** pieces that would fall outside glow red. Confirming shows a warning, e.g. "6 pieces will be removed and refunded to your storage. Proceed?" (Proposed destination: warehouse, else nearest chest with room, else a crate dropped at the plot.)

**Templates**

- **Build it yourself or use a template.** A placed template becomes ordinary pieces the player can change.
- **Placing:** the template shows fully built with real textures, plus a green or red outline glow for valid or invalid spots (too steep, blocked, colliding).
- **Confirming:** it turns into blue ghost outlines that show each piece's cost, plus overall progress (e.g. "Forge: 14/32 pieces").
- **Filling:** the player hits a ghost piece with the hammer while carrying its materials. Building uses only what is in the player's inventory, not storage. Ghost pieces can be removed or swapped for free before they are built.
- **Player templates (proposed):** players save their own builds as templates.

**Storage and builders**

- **Chests:** the player's personal storage. NPCs never touch them.
- **Warehouse:** town storage the player can open. NPCs drop their daily output here.
- **Builder NPCs** fill ghost pieces from warehouse stock. First version: materials come straight from the warehouse. Later, once NPCs can walk around the town, builders carry loads from the warehouse to the site.

## World and look

The valley is built from real-world elevation data and is heading toward a realistic natural look, with steampunk ruins layered on top.

- **Terrain:** a heightmap of rolling hills in the English Midlands (36 to 226 m real elevation), built in chunks. Currently 1500 m across with the hills exaggerated. The rest of the heightmap is room to expand, and airship travel can open new regions later.
- **Water:** a single water level fills the low ground, forming the river and lake.
- **Visual target:** a realistic forest-and-stream look like the reference screenshot (rocky slopes, ferns, deer). Lighting, fog, shaders, and procedural grass come first; real art assets (Poly Haven, ambientCG, asset packs) replace placeholders in a later beauty pass.
- **Places to discover:** the ruined airship dock, an abandoned workshop, and rusting machinery in the hills.
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

## Current build status

The first-era survival loop is playable: walk, gather, chop, eat, build a fire, and survive the night.

**Working**

- First-person movement, mouse look, and jumping
- Day/night cycle with warm sunsets and dark nights
- Real-world heightmap terrain in chunks, with water filling the low ground
- Visual pass: slope-based ground coloring, grass, rocks, improved trees, water shader, haze
- Gathering scrap, coal, and berries with E, with an on-screen counter
- Tree chopping: 4 hits, the tree falls, a stump remains, +3 wood
- Hunger and warmth meters; eat berries with F; build a campfire with B for 3 wood
- Inventory screen on Tab with 20 slots
- Free building with snapping wooden pieces, square and round (see Building system)
- Compact steampunk-brass HUD, laid out at 1920 × 1080 and scaling with the window (same look at 1080p and 4K): the brass vitals panel bottom left (`assets/ui/vitals_panel.png`: a half-gauge whose needle shows warmth, red zone at full, over hunger and warmth channels that fill gold and orange-red with soft ends), the brass compass with its small clock mounted on the action bar's left end (the bar's own left scrollwork is trimmed off), drawn on top, its brass right up to slot 1's frame and its loose side curls tucked under it (`compass_clock.png`: a needle pointing north relative to where you face, hour and minute hands showing the in-game time), a thin brass ring crosshair, what E and F would do in a line under the crosshair, and a centred row of the controls that apply right now just above the action bar (label and key badge pairs), with a small panel above it while building or demolishing (piece icon, name, cost or refund, one line of details). The action bar is the brass bar art (`action_bar.png`) with a slot picture over each opening: a plain slot when it holds something, a gear slot when empty, and a gold, glowing slot for the selected one. Menus are drawn 1.5× (`MenuStyle.MENU_SCALE`). The blank brass plaque (`plaque.png`, 9-sliced just inside its corner rivets, edges stretched) frames the build placement panel, build menu, inventory, crafting and pause menus; the title screen alone uses the ornate `panel_frame.png`. Buttons, slots and key badges keep a restrained code-drawn brass style (`ui/brass_style.gd`: thin bevelled worn-gold borders, recessed slots, a faint gear in empty inventory slots). Anything missing from `assets/ui/` is drawn in code

**Known issues**

- Eat and campfire prompts show even when the player has no berries or wood
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
