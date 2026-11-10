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

## Opening quests

The first quests teach survival, then lead straight into the settlement game.

1. **Survive:** craft the first tools, build a lean-to, and build a chest.
2. **The ruined castle:** the quest marker moves to a ruined castle, where the first two refugee NPCs are sheltering. They need a home and point the player to a valley down the road, a good place to build.
3. **A house:** build a House there for them.
4. **Food:** once housed, they need food, which leads to the Forager's Hut and learning to assign jobs.

## Progression

Four eras take the player from scrap to the sky, and each era's technology also raises the Hollows' attention.

| Era | What the player builds | Key resources | Main threat |
| --- | --- | --- | --- |
| 1. Scrap and Survival | Stone tools, campfire, rough shelter | Stone, plant fiber, sticks, wood, scrap, berries | Cold, hunger, wolves |
| 2. The Forge | Smelter, forge, workshop, bronze tools | Copper and tin, smelted into bronze; zinc for brass (proposed) | Lone Hollow scouts drawn by forge smoke |
| 3. Steam Power | Sawmill, water wheel, steam pump, steam shovel, walls and steam defenses, clockwork helpers | Iron and coal from underground, steel (proposed), gears, springs, copper plating from Hollows | Hollow raiding parties |
| 4. The Sky | Restored airship dock, trade with passing airships, own airship, clockwork guardians | Aether from capped vents, aluminum for airship frames, construct cores, trade goods | A major Hollow assault drawn by the dock's engines |

**How technology unlocks.** Two routes, mixed:

- **By doing:** chopping, mining, and crafting teach the basics (Medieval Dynasty style). Basic T1 items keep unlocking this way.
- **By discovering:** after T1, the tech tree takes over (see below). Hollow parts studied at the workshop feed it too.

**Tech tree and exploration (after T1)**

- **Schematic fragments** are the research currency, found while exploring.
- **Big points of interest** (the ruined castle, the airship dock, the abandoned workshop) hold whole schematics.
- **The tree:** it shows every era's buildings and tools from the start, each locked until bought with fragments. Some nodes also need an earlier node, or a working building of some kind.
- **Researching** happens at a research table in the Workshop.

**Underground resources.** Iron and coal don't sit on the surface. The player has to craft a prospecting tool to find deposits (ideas: a dowsing rod early, then a brass prospector's scope or seismic thumper), then dig or drill to reach them.

**A building for each tier.** Every tier adds its own production buildings, for example a smelter and forge for bronze, a blast furnace for iron and steel, an aether extractor, and an airship yard.

**Aluminum (proposed lore).** As in the real 1800s, aluminum is rarer than gold because refining it takes enormous power. Aether-powered refining is what finally makes it possible, which ties the last tier together. It is the lightweight metal for airship building.

## Threats

Early danger comes from the land; later danger comes from the Hollows, and the player's own progress is what calls them.

- **Survival pressure:** hunger and stamina meters. Planned: seasons with a harsh winter that needs steam heat, and tools that wear out.
- **Stamina (0–100):** sprinting costs 12 a second, a jump 8, and a tool swing (chopping with the axe, mining with the pickaxe) 6. It comes back at 20 a second once none has been spent for 1 second. At 0 you're winded: no sprinting or swinging until it's back above 15 (walking and jumping still work). Hunger lowers it: well fed you have the full 100 and full regen; starving, at most 50 and half regen, easing in between. A night's sleep refills it. Saved with the game.
- **Warmth (switched off for now):** warmth and the cold are kept in the code but switched off with one project setting, `game/survival/warmth_enabled` (false). While off there's no warmth meter, no cold damage or slowdown, and no freezing, sheltered or indoors messages; fires still give light, and the shelter and closed-room checks still run (beds and settlers will need them). Older saves load without their warmth. **Warmth returns for cold regions (such as the Frost Highlands) and winter**: then it drains at night and in the open, more slowly under a roof, not at all in a closed room, and fires, the fireplace and a held torch warm you; it will need its own meter on the HUD.
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

- **Settlers:** other refugees arrive once there is housing and food. They come from campsites (see World and look): some campsites have a refugee who joins if there's a free bed.
- **Settler and job plan:** the order is settlers first, then the forager and food, then crafting buildings.
  - **Forager:** a fixed daily amount, split by percentages the player sets (no foraging area).
  - **Food:** each settler eats about 2 food a day.
  - **Crafting buildings (later):** they get NPC workers, and the player can still use their stations. NPCs keep stock targets (e.g. "keep 40 planks") using ingredients from the warehouse.
  - **Still open:** where the player's own crafting ingredients come from, how many workers each building takes, and whether NPCs can craft recipes the player hasn't unlocked.
- **Jobs:** settlers work at a workplace plot (woodcutter, miner, stoker, farmer). At the end of each day their output is calculated and added to the warehouse, so later in the game the player no longer has to grind for materials.
- **Built so far (settlers, first version):** settlers are simple low-poly placeholder figures in refugee clothing (tunic, trousers, scarf, hair or hood or cap, some with a bedroll on their back; colours, height and build vary per settler), each with a random name (`settlers/`).
  - **Arrival (temporary, until campsites exist):** each morning, if a working House has a free bed, one refugee arrives, walking in from about 56 m away toward the nearest valley edge, and moves into that House: "A refugee named Name has arrived." At most one a day. F9 (debug builds only) brings one at once, a few steps in front of you.
    - **Where they appear** (dawn arrivals and the console's `spawn_settler` alike, `SettlerManager.find_safe_spot`): on the visible ground. It looks straight down from 80 m above the terrain, and the first thing hit must be open ground, not a building piece, tree, rock or landmark. The spot must also be dry, no steeper than 32°, clear of the wreck, the castle and rock outcrops, outside building footprints, and at least 1.5 m from any piece. If the first spot fails, it tries rings out to 75 m (8 spots each, each also moved onto the settlers' navigation where it's ready); a dawn arrival then tries beside the House. If nothing works, nobody comes that day.
    - **Logging:** every attempt goes to the console output, prefixed `[Settlers]`. That includes why nobody arrived at dawn (no House, a House not working, no free bed with residents/beds), each spot tried and why it was turned down, and where the settler was placed.
  - **Walking:** Godot navigation, baked at runtime in 32 m tiles around every plot (64 m to spare) and every settler, from the valley's heights (water left out) and the solid shapes on them (pieces, furniture, the workbench, chests, campfires, trees, rocks). Doors are left out, so settlers path through doorways. Once a second each tile's pieces are compared with when it was baked; a tile where something was placed, demolished or moved is baked again, one tile per frame. Settlers step up low ledges (floors on the ground, thresholds up to 0.5 m), open closed doors as they reach them (doors never block them), and close the ones they opened behind them.
  - **Talking:** E aimed at a settler opens their panel (brass plaque): name, home, job, status ("Working at Forager's Hut", "Walking to…", "Heading home", "Sleeping", "Idle: no job", "Can't work: missing roof"), with Assign home and Assign job, each listing the working plots with a free place (plus No home or No job).
  - **Homes and jobs:** a House holds one settler per bed, each sleeping in a bed of their own (beds in the order they were built, residents in the order they arrived). The Forager's and Woodcutter's Huts take 1 worker each (`PlotType.workers`, standing at `PlotType.work_at`: the foraging basket or chopping block); the Workshop and Storehouse come later. The plot panel lists a House's residents and a workplace's worker (with Unassign); the plot tracker has a line for them too.
  - **Daily routine (the sun's clock):** from 0.28 to 0.70 they work, bent over their workplace's furniture, now and then wandering a little inside the plot; in the evening they go home and idle there; from 0.78 to dawn they sleep in their bed. With no job they idle around their home; with no home they sleep by the nearest campfire or fireplace (or where they stand). A workplace that stops working leaves its worker idling there, showing "Can't work: reason".
  - **Daily output (at dawn, 0.27 on the sun's clock):** each working workplace with a worker makes its day's amount into town storage (the working Storehouses; see Storage and builders) while it has room, otherwise into its own storage chest.
    - Forager's Hut (the gatherer's hut): 35 items a day, shared out by sliders among berries, herbs, mushrooms, plant fiber, stone, copper ore and tin ore.
    - Woodcutter's Hut: 12 wood and 8 sticks.
    - A hungry worker makes half.
    - **Stone and ores:** the separate Stone Gatherer's Hut is gone; stone, copper and tin come from the Forager's Hut. A save's old Stone Gatherer's Hut loads as a Forager's Hut if it meets one's requirements (renamed if it still had the old name), otherwise the plot is dropped and its pieces stay standing, owned by no plot; either way a message says which (`PlotRegistry._settle_old_plots`). The Stone Sorting Table stays as furniture, decoration only now.
    - **Later:** iron and coal will come from a mine that villagers work at.
    - What won't fit in either (no free slot for a new kind of item; slots hold any amount) is lost, with a message: "Forager's Hut: Town storage full (3 herbs lost)" ("chest full" with no working Storehouse).
    - All three workplaces require a storage chest of their own, so a working one always has somewhere for its output. Should one somehow have none, the day's output is lost, with a message.
    - The amounts are data on each plot type (`daily_output`, `split_output_total`, `split_output`).
  - **Forager sliders:** a Production section in the Forager's Hut plot panel has sliders for berries, herbs, mushrooms, plant fiber, stone, copper ore and tin ore, always adding up to 100%. Moving one shares the rest among the others in their current proportions. Each shows the resulting amount per day. The default is 30/12/12/6/24/8/8 (11 berries, 4 herbs, 4 mushrooms, 2 plant fiber, 8 stone, 3 copper ore, 3 tin ore), saved with the plot; a save's older four-item split starts again from that default. The other workplaces' Production section lists their fixed output.
  - **Food (at dusk, 0.74):** each settler eats 2 food, berries first, then mushrooms.
    - It comes from town storage first, then the nearest storage chest of a working plot that has any, then any other storage chest inside a plot (working or not). Chests outside every plot are the player's personal chests: settlers never eat from them.
    - A settler who can't eat their fill is Hungry, shown as "Hungry (n days)" (or "Fed") in their panel and "(hungry)" in the plot tracker and plot panel.
    - Hungry settlers produce half. After 3 hungry days in a row they leave the settlement, walking off toward the valley's edge, with a message.
    - A House's tracker shows "Food stored: n days": the food in town storage and every storage chest inside a plot, for everyone in the settlement, since they all eat from the same stores.
  - **Debug:** F10 (debug builds only; the developer console's `day`) skips to the next dawn: tonight's meal first if it hasn't happened yet, then the day's output and any arrival.
  - **Saved:** name, look, home, job, position and hungry days; the slider percentages with each plot; which day's dawn and dusk have been handled.
  - **Day counter fix:** sleeping from before midnight now counts as the next day.
- **Defense:** walls, watchtowers, and steam-powered defenses against Hollow raids.
- **Clockwork guardians:** late game, reprogrammed construct cores become defenders, turning the Empire's weapons against its ruins.
- **Terraforming:** a craftable, coal-fuelled steam shovel raises, lowers, and flattens ground for foundations, ponds, and channels from the river. Height-based only, so no caves or tunnels. It needs a save system so changes persist.

## Building system

The player builds freely with Valheim-style snap pieces, and plots turn those structures into working buildings. Free building stays closer to RuneScape: Dragonwilds than to Medieval Dynasty's set build stages.

**Pieces**

- **Building visuals:** pieces are rustic geometry built in code (planks, shakes, logs, stacked stone, rope) in weathered grey-brown, matching the cabin reference image. Furniture uses Meshy models fitted to exact boxes.
- **Snap pieces:** foundations, walls, floors, roof sections, stairs and doors that snap to each other corner to corner, as in Valheim (see Placing pieces, below).
- **Round builds:** curved wall arcs (22.5° and 45°) that close into full circles, round tower kits (circular floors, cone roofs, spiral stairs), and 22.5° rotation steps (1° steps with Shift held).
- **Not voxels:** Enshrouded-style smooth voxel building was ruled out as too big for a first project, and it would not fit the existing terrain.
- **Built so far (first version):** wooden pieces in the hammer's build menu, under tabs (Foundations, Floors, Walls, Roofs, Beams & Pillars, Stairs & Doors, Round, Other; Q and E change tab). Square pieces (2 m grid, 1 m half step): wood and stone foundations (solid blocks 3 m tall that go 2 m into the ground, stacking and snapping side by side; floors, walls and stairs snap onto their tops like onto floors), floor, wall (2.5 m high), doorway wall (opening 1.2 m wide and 2.2 m tall, so you walk through with the door open), door (E opens and closes it), window wall, 26° roof (rises 1 m over 2 m), stairs, and wood and stone pillars (on floor and foundation corners and edge middles, stacking; floors, walls and roofs sit on their tops, for platforms and porches). Triangles combine with the squares: a right triangle (half a square, long side 2.83 m) and a 45° triangle (two 2 m sides at 45°, short side 1.53 m, filling the gap between squares turned 45°, so squares and triangles make an octagon), each as a floor and a wood and stone foundation, with long (2.83 m) and short (1.53 m) walls for their odd sides. *Round* (one ring, radius 2.61 m, so a 45° arc spans 2 m and eight close a circle 5.2 m across): wood and stone round foundation wedges, curved walls (45° and 22.5°), round floor wedges and cone roof wedges (eighths), and 22.5° round floor and foundation wedges (sixteenths) to match the 22.5° walls. A round wedge's curved edge lies exactly under the curved walls' middle line. Every piece unlocks with the first planks. Pieces are placed and snapped as described under Placing pieces, below; free, they go wherever the crosshair is, sitting on the ground or on other pieces, and may float. Tab while placing opens the build menu: picking something switches to it (at the same turn), and closing it goes back to what you were placing. Pieces may overlap anything (see Overlapping, below). Demolishing is direct: with the hammer out, placing or not, pressing the middle mouse button on a piece makes it glow red, and letting go removes it for a full refund with a short message ("Demolished Wall (+4 Planks)"); looking off it before letting go cancels, and placing carries on afterwards with the same piece and turn. Holding X on a piece does the same for mice without a middle button (it glows red with a percentage while held; letting go early cancels). Nothing glows or gets removed otherwise. What won't fit in a full backpack is left in a bundle on the ground, picked up with E. Under a roof counts as shelter; a closed room (floor, walls, roof, door shut) stops the cold entirely, round rooms included. Floors and foundations keep the grass out. No structural support yet. Shapes: `building/pieces/piece_shapes.gd`; each piece is a `PieceBuildable` in `buildables/structure/` or `buildables/round/`, and can show a real model instead of the plain shape (`model_scene`). Wood pieces are textured with Poly Haven's Wood Planks Dirt and stone pieces with Rock Wall 13 (2K copies; 4K originals in `assets/textures/hd/`, outside git), mapped at real-world scale (one copy covers 2 m) in a frame that follows the building, so planks run on across neighbouring pieces without seams: level on walls, along floors, down the slope on roofs and overhangs, round the curve on curved walls and round floors, along beams and up posts (`building/pieces/piece_surface.gdshader`). Each piece gets a slight colour and brightness of its own, and darker grime toward its edges and the foot of upright faces. That plain textured box is now only the distance version (beyond 60 m). Close up, every piece is built in code from real parts in warm weathered grey-brown timber (around #7d705f; the wood texture's light blotches flattened, its dark grain kept, each plank's narrow sides and bevelled edges darkened), tan-grey stone (around #8a8272, dirtier lower down) and thick brown hemp rope (around #8b6f47) (`building/pieces/piece_detail.gd`, `piece_detail.gdshader`): walls of separate bevelled horizontal planks (random thickness, height, tilt, ends and gaps) over a dark core, chunky plank frames round doorways and windows, a door of vertical planks with iron strap hinges and a rope pull, gables of planks with a king post and brace, floors of rough planks with gaps, wood foundations of stacked logs, stone foundations and pillars of irregular bevelled blocks with dark mortar, stairs of plank treads on log stringers, and roofs, corners, eaves and overhangs of decking under overlapping rows of split shakes (a few out of place), with rafter tails under the eaves and fascia and barge boards round overhangs. Each shape has 8 versions, picked by the piece's id, so a piece looks the same after loading and neighbours differ. Log corner posts with rope lashings stand wherever walls meet at an angle, a log with rope ties runs along every ridge where two roofs meet (unless a ridge cap is there), and every foundation edge not shared with another foundation gets a lip of stone (or logs) reaching 12 cm past it, so walls sit on top with stone showing; all three are worked out from the pieces once they've stopped changing for 0.2 s (one rebuild after a template's ghosts all go in, not one a frame) and aren't saved (`building/pieces/joint_details.gd`). Pieces keep their exact size, corners and collision. Furniture keeps its own look. Every piece has an id and an owner plot, listed in the `PieceRegistry`, which also saves them.
- **The small kit (Valheim-style):** a 1×1 m floor; 1 m walls, half-height walls (2 m and 1 m wide, 1.25 m high) and a 1×1 m quarter wall; gables (wall triangles) for the 26° and 45° roofs, standing on the wall under a roof end; a 45° roof, and for each pitch an inner corner (valley), outer corner (hip) and ridge cap; beams (1 m, 2 m, and diagonals at 26° and 45°) and poles (1 m, 2 m), which snap by their ends; a 2 m ladder (hold W while facing it to climb); railings (2 m, 1 m) and a 2 m fence. All snap by their corners (see Placing pieces). Roof panels have both ends cut plumb, so two roofs back to back meet in a sharp, closed peak (the ridge cap still sits over it) and the eave end reads as a cut rafter end; existing roofs pick this up when loaded. Overhangs, for each pitch (Roofs tab): an eave (2 m wide, 0.5 m out, carrying the roof's slope on outward and down; 1 plank, 1 plant fiber) for a roof's or hip corner's low edge, a gable overhang (0.5 m wide, 2 m along the slope; 1 plank, 1 plant fiber) for a roof's side edge, past the gable wall, and an eave corner (0.5 × 0.5 m; 1 plank) under a gable overhang's low end where it meets the eaves. They match the roof's thickness and plumb cuts, have a fascia board along their outer edges, tuck over wall tops and gables, and don't count as roof for shelter.
- **Heights that line up:** a full wall is 2.5 m. The 26° gable rises 1 m and the 45° gable 2 m above what it stands on, and half walls are 1.25 m and the quarter wall 1 m. Two pieces make up the difference:
  - the 45° gable wall: 2 m wide, 0.5 m tall at its low end, rising at 45° to 2.5 m (a full wall's height) at its high end; it stands on floors like a wall, so a sloped wall's tall end meets a full wall's top;
  - top-up strip walls, 0.5 m tall, 2 m and 1 m wide: a 45° gable on a strip is 2.5 m too.
  Corner posts follow a sloped wall's height at each end.
- **Triangle wall pieces** (Walls tab, 26° and 45°, rustic planks with a post up the vertical side):
  - **Half gables, 1 m** (1 plank): a right triangle, flat bottom, vertical side, the slope on top; half a 2 m gable (the 2 m gables are already this shape).
  - **Inverse triangles, 2 m and 1 m** (2 planks, 1 plank): the space above a slope, under a flat line, with the sloped edge along the bottom, a flat top and a vertical side at the low end.
  - Both snap by their three corners, on the panel's centre plane (see Placing pieces).
  - A half turn (180° with the wheel) mirrors either left and right (the planks are the same on both faces).
  - **Seating:** the pieces' plank infill and dark backing reach 2 cm past their edges into what they meet, so no light shows at a joint; the post and rail trim keep to the true edges.
  - **Filling a 45° gable end around a 26° gable:**
    - The high half takes a 1 m 26° inverse triangle on the gable's slope, with a 1 m 45° half gable on its top.
    - The low half is a sliver between the two slopes. It's closed by a 1 m 45° half gable standing over the gable's low half; pieces may overlap.
- **Topper gable** (26° and 45°, Walls tab, 1 plank): the triangle under a roof topper's end, 2 m along the bottom at the roofs' high edges' height, peaking under the topper's peak, in planks with a sill and a king post.
- **Wall-mounted and wall-backed furniture:** aiming at a wall's face, furniture that backs onto walls (bed, storage shelf, tool rack, storehouse storage, firewood rack, workbench) stands flush against that face, on the side aimed at, facing out of it, slid along the wall on the 0.25 m furniture grid.
  - Wall-mounted furniture (the tool rack) hangs instead of standing: its bottom 1.0 m above the wall's foot, pegs about 1.2 to 1.6 m up.
  - Aiming at the floor near a wall still backs it up to the wall, now from its front, so a spot that starts inside the wall comes out on the near side.
- **Placing pieces** (the Valheim model, and the only one. Code: `building/valheim_placer.gd` (`ValheimPlacer`), snap points `building/snap_corners.gd` (`SnapCorners`)):
  1. **The target:** a ray from the crosshair (8 m). The building piece it hits is the target, tinted blue. Snapping uses only the target's snap points and those of the pieces directly touching it (their boxes within 0.1 m of its box). If it hits the ground or nothing (then the spot is the ground below the end of its reach), there's no target and the piece sits free on the surface, with one exception: aimed at the ground right beside a building, the piece whose snap points come within 0.5 m of the ghost's corners there (the closest) is the target, and the piece snaps to it. That's how a floor goes beside a floor, or into a hole in a floor at ground level.
  2. **Snap points are corners and ends only,** worked out from each piece's exact solid shape: floors and foundations at the corners of their top (squares 4, triangles 3, round wedges the circle's middle and both ends of the arc); walls, doorways, windows, half and quarter walls, railings, fences and ladders at the four corners of their centre plane; gables, half gables and inverse triangles at their three corners; roofs, roof corners, ridges, eaves, toppers and overhangs at the corners of their underside (a roof's two low corners sit on a wall top's two corners); curved walls at both ends of the arc, bottom and top; ridge caps at both ends of the middle line they sit on the ridge by (it lies on the roofs' high corners); beams, poles and pillars at both ends; stairs at their four corners (the bottom edge's and the top edge's ends); chimney sections at the eight corners of their box. A doorway also has the door's two bottom corners where the door goes, and the fireplace and each chimney section have the next section's bottom corners where it stacks. Furniture has none. Nothing in between: no edge middles, no points along edges, no default or attach points, and no choosing one.
  3. **Showing it:** the target is tinted a strong light blue (as in Valheim's screenshots), its snap points show as small yellow dots (while snapping), and the pair in use gets a yellow upright bar. No dots on anything else. The ghost is the piece's real look (its full close-up look, or its model) at 70% opacity, turning red only where it can't go: an identical piece already there ("Already placed") or not enough materials ("Not enough: …").
  4. **Turning:** the wheel turns it 22.5° a notch, measured against the target, so 0° is lined up with whatever you're pointing at (with no target, with the world). The turn stays until the player changes it, across pieces (and furniture, workbenches, chests and campfires) too. The game never chooses or changes the facing. Holding Shift places it free, without snapping, and the wheel turns 1° a notch while it's held.
  5. **The snap:** the ghost goes at the crosshair's hit by its hold point, at the player's turn. The hold point is its origin (a floor's or foundation's top middle, a wall's bottom middle, a roof's low edge middle, a pole's or pillar's foot, a beam's middle), except: a roof topper is held like a roof, by the middle of one low edge, so aimed at a roof's high edge it reaches on over the ridge; and a piece whose origin isn't on it (curved walls and cone roofs, whose origin is the middle of the circle) is held by the middle of its base (`ValheimPlacer.hold_point`). Then the closest pair between its corners and the target's corners (and the touching pieces') decides, and the ghost slides so they meet exactly, with three rules:
     - **Never into the target:** a pair that would sink the ghost more than 5 cm into the target or a piece touching it is skipped, and the next-closest taken (`building/piece_overlap.gd`, measured on the pieces' exact solid parts). So a floor aimed at a floor's middle lands beside it, on the side the crosshair is nearest, and a turned half wall never jumps into the half wall it's on. Pieces that touch, stack, sit side by side or meet in an L don't count. Slender pieces (pillars, poles, beams, ladders) never count, because their ends are meant to sit into what they carry.
     - **Edge to edge first:** a pair where two or more of the ghost's corners meet (side by side, stacked) wins over a point-only one, unless that one is more than 0.25 m closer.
     - **Ties:** of two pairs within 15 cm of each other, the one on the target corner nearer the crosshair wins, then the one whose own corner is nearer the camera, so the piece reaches away from you (aimed at a pole top, a beam's near end meets it).
     Aimed at the target, the pair may be up to 3 m apart; aimed at the ground beside a building, up to 0.5 m (rule 1). Nothing else: no best fit beyond that, no trying other angles, no aiming into the air, no automatic facing.
  6. **Sticky corner:** once snapped, the ghost keeps the same target corner while the player turns it, only re-picking which of its own corners meets it, so it swings round that corner. It moves to a different target corner only when the crosshair gets more than 0.3 m nearer that one. Aimed at the ground beside a building, the sticky corner holds while the crosshair stays within the ghost's size of it.
  - **Regression test** (`tests/snap_regression.gd`, run headless: `godot --headless --path . res://tests/snap_regression.tscn --quit-after 40000`; CLAUDE.md asks for it after any change to building, snapping or placement code): opens a fresh world, builds each case on flat open ground and places through the real placer with the real crosshair and real input events sent through the input system (the mouse wheel, and Shift held down), never setting the turn or an aim point itself (it turns the piece with wheel notches). Cases: a floor aimed at the ground beside a floor (in the square beside it, lined up); a floor into a 2×2 hole at ground level, and turned 4 notches there (still filling it, planks turned 90°); a wall on a foundation edge (corner to corner, the foundation the target, its four corners as the only dots, the bar on the pair in use, the ghost 70% opaque, and snapping elsewhere rather than into an identical wall standing there); a floor aimed at the middle of a floor (beside it on the nearest side, not on it); a half wall on top of a half wall, a wall beside a wall and a floor beside a floor, each turned a full 360° notch by notch (always on the same target corner, never sunk in, flush again at 0°); a doorway between two walls (its four outer corners on the walls' ends); a roof on a wall top turned 8 notches to face over the room (low corners on the wall top's, rising over the room); a pole on a floor corner, and a beam from pole top to pole top; stairs at a foundation edge turned 8 notches (bottom corners on the edge's, climbing over it); a pillar-top fan at 0°, 22.5°, 45° and 67.5° (a corner on the pillar top each time); Shift held (free at the crosshair, the wheel 1° a notch) and let go (snapped again); and every buildable (corners for every building piece, none for furniture except the fireplace's chimney spot; the wheel 22.5° a notch; the five controls). Then the **snap audit**: each of the 101 buildables at its usual target (floor beside floor, triangle floors and foundations on a square's edge, round wedges side by side, walls on a foundation or 1 m floor edge, long and short walls on the triangle foundations' odd edges, gables on wall tops, inverse triangles on a gable's slope, roofs and outer corners on a wall top rising over the room, inner corners beside a roof, eaves on a roof's low edge, gable overhangs on its side, eave corners at an eave's end, ridge caps, toppers and hip ends on a roof's high edge, topper overhangs and gables at a topper's end, curved walls on a round floor's arc, the cone roof on a curved wall, posts on a floor corner, stairs and Foundation Steps hanging down from an edge, a ladder from a floor corner, the door in a doorway, chimneys on the fireplace and each other, beams pole to pole, furniture on a floor). Where it should end up is worked out from the two pieces' corners; it's turned there by wheel notches and aimed at with the real crosshair, and must snap, meet the corners it should, land exactly there and not sink into the target. One `SNAPAUDIT` line per buildable. Each check prints SNAPTEST PASS or FAIL, then a summary; the exit code is the number of failures. Last run: 28 passed, 0 failed (the audit: all 101 right).
  - **The wheel while placing:** with the mouse captured, the player takes mouse wheel events in `_input`, before any part of the screen can catch them, and hands them to the placer (so a panel under where the hidden cursor rests can't swallow the scroll, and the action bar doesn't move).
  - **Cost:** each shape's corners are worked out once; a target's points with its touching pieces' are worked out once and kept until pieces change. Only the target (or, aimed at the ground, the pieces within a few meters) is looked at.
  - **Foundation Steps** (Stairs & Doors tab, next to Stairs; 2 planks): a short flight 1 m tall (a foundation's height above the ground), the same width, slope and look as Stairs, in 4 steps (1.6 m long). Its icon is drawn by the icon updater on the next debug launch.
  - **Building controls (Valheim's, and nothing more):** placing any piece, furniture, workbench, chest or campfire uses only these, and the controls row shows just these five: left click places ("Place [LMB]"); the mouse wheel turns it 22.5° a notch round the upright ("Turn [Wheel]"); holding Shift places it without snapping, and the wheel turns 1° a notch while it's held ("No snap (turn 1°) [Hold Shift]"; some mice send Shift + wheel as a sideways scroll, which turns 1° too); the middle button demolishes ("Demolish [MMB]", Hold X too; `building/demolisher.gd`); right click cancels ("Cancel [RMB]"). Furniture and the workbench, chest and campfire stand on the floor, foundation or ground under the crosshair (`building/furniture_spot.gd`): on a floor's 0.5 m grid in its own frame, or flush against a wall they back onto (the tool rack hangs on it), turned by the same turn about where they stand, measured against the floor or wall.
  - **The placement panel** shows just the piece, its cost, and its turn when it's turned ("Turn 45°", "Turn 22.5°"; nothing at 0°), plus why it can't go there (red).
  - **Saved rotation:** saves and templates keep a piece's whole rotation (a quaternion beside its turn), so pieces saved tilted or tipped from before load exactly as they were; older saves without it load as before.
  - Diagonal beams are a few millimetres off-centre front to back, so crossing ones never share a face and don't flicker.
- **Roof topper** (26° and 45°, Roofs tab, 2 planks and 1 plant fiber): closes the ridge on buildings an odd number of foundation tiles across. On a 3-tile (6 m) building, one 2 m roof up each side leaves a 2 m gap at the ridge.
  - **Shape:** 2 m along the ridge, bridging the 2 m gap (1 m down each side from the peak), sloping at the roofs' pitch on both sides: two short roof slabs back to back with decking and shakes like the roofs, and a log ridge beam with rope ties on top. It counts as roof for shelter.
  - **Snapping:** by the corners of its underside, like a roof: its low corners meet the high corners of the roofs either side.
  - **Topper overhang** (26° and 45°, Roofs tab, 1 plank and 1 plant fiber): the topper's gable overhang. It carries the topper's end 0.5 m on past the gable wall, with the same shakes on both slopes, the ridge log running on to its end, and barge boards down both sides of both slopes. Like the other overhangs, it doesn't count as roof for shelter.
- **Hip roofs** (26° and 45°): one end of a building sloped as a hip, the long sides' roofs carrying on to a ridge that runs into a gabled roof (or another hip) at the other end.
  - **Rows:** roof panels stack up the slope on the long sides (each row's low edge on the high edge of the row below) until they meet at the ridge, and sit end to end with the panels beside them along the building (their side edges), so the slopes run straight on into a gabled roof of the same pitch and height.
  - **Hip corners** (outer roof corners) at the building's corners, and end panels between them along the hip's eave. On a wider end the corners stack: a corner's low corner goes on the top corner of the one below, the same way round, so the hip line carries straight on up (on an 8 m wide end, the second corners meet at the ridge).
  - **Hip End** (Roofs tab, 2 planks and 1 plant fiber): closes the top of the hip on a building an odd number of tiles across (6 m: the side roofs stop 2 m apart, as under a Roof Topper). It covers the 2 × 2 m square between the side roofs' high edges, above the end panel: three faces (the end's, rising with the hip's slope, and the two side roofs'), the two hip lines rising from the hip corners' tops to its apex 1 m in, the ridge running on from the apex to its far edge, which has a topper's cross-section. Close up, hip logs run up both hip lines to the apex and the ridge log runs on from it.
  - **Snapping:** hip corners and the Hip End snap by the corners of their underside like any roof piece, turned by the player to face the right way.
  - **Ridge closure:** Roof Toppers along the ridge from the Hip End into the gabled roof's toppers (odd widths); ridge caps on the ridge where the side roofs meet back to back (even widths). The ridge logs carry on with no step.
  - Gables close a hip-to-gable roof's gabled end as usual; a gabled roof whose ridge is lower or turned another way can't be joined straight on (its slopes would have to meet in a valley).
- **Outer eave corner** (26° and 45°, Roofs tab, 0.5 × 0.5 m, 1 plank and 1 plant fiber): the valley eave corner's opposite, for outside corners where two eaves meet round an outer roof corner (hip) or a building's corner.
  - **Shape:** its top follows the lower of the two eave slopes, folding down along the diagonal, with level fascia boards on both outer edges meeting at the corner.
  - Like the valley eave corner, it shows its plain textured look close up.
- **Split-window walls** (Walls tab): a window cut into one side edge, so two side by side (one turned half round) make one wide window across the joint.
  - **Sizes:** 2 m (3 planks) has a 1 m opening, so two make a 2 m window; 1 m (2 planks) has a 0.6 m opening, so two make 1.2 m. Both are 1.1 m tall from the window wall's sill height (1.1 m).
  - **Trim:** the sill, header and side post are on the solid side only, and the sill and header run right to the open edge, so the joined pair reads as one window with no post in the middle.
  - **Snapping:** by its four corners, as for other walls. There's no corner post where two open ends meet, even at a corner.
- **Icons for new pieces:** a piece whose file names no icon uses `assets/icons/build/<shape>.png`, which the icon updater draws on the next debug launch from the project. The build menu picks it up once the editor has imported it.
- **Templates** still fit their outside to pieces already built using the pieces' typed points and `PieceShapes.SNAP_RULES` (see Templates); placing pieces by hand doesn't use them.
- **Overlapping (Valheim-style freedom):**
  - **The player doesn't fight the building system.** Placing pieces, furniture and the workbench, chest and campfire, laying out templates, building ghosts and moving plots all work the same way:
    - **Overlap anything:** they may overlap or clip into other buildings' pieces, furniture, workbenches, chests and campfires, plots, trees and rocks, snapped or free, without turning red.
    - **Any depth:** pieces sink into the ground as far as you like, with no note.
    - **People glide aside:** you or a settler standing where something lands don't stop it: it goes down, and whoever is inside it glides (a quarter of a second) to the nearest open spot beside it: the nearest place out to 8 m where a person fits standing on the ground or a floor, no more than 2 m up or down, never on top of what was just put down (`building/people_mover.gd`). A sleeping settler (lying in bed or by a fire) isn't solid, so isn't moved.
  - **Only two things stop one:** an identical piece already there, within 5 cm and 5° (allowing for the shape's symmetry, ghosts included): "Already placed" (red); and not having the materials (red too, while placing a piece).
  - **Measured** through the real placers on the day-4 save (under the earlier placer): the Basic House moved 28 m onto the Storehouse (30 of its pieces within 4 m) and 8° ground, placed with no warning; a foundation put down where a settler stood placed, and the settler glided 1.6 m to the ground beside it.
  - **Plots:** a piece whose middle lands in no plot places normally, as a free piece belonging to none, even while you stand in a plot.
  - **Templates:** pieces that would exactly repeat ones already there (a wall shared with the building beside it) are left out when the template is placed.
  - **Warnings (yellow, still placeable):** steep ground under a template's foundations or under a moved plot, and steep ground or water under a workbench, chest or campfire.
  - **Physics:** placed pieces are still solid to walk into, and settlers still path round them.
  - **No flicker:** each piece's look sits up to 2.5 mm off its true place, in a direction of its own (from its id), so faces of overlapping pieces that lie in the same plane don't flicker.
  - **Old rules gone:** the old rules (the roof tolerance, chimneys passing through roofs, slender pieces and overhangs only bumping each other, rocks in the way, people in the way, the ground-depth limit, moved buildings running into others) are gone. Furniture still backs up against walls.
- **Valley eave corner (each pitch, Roofs tab; 1 plank, 1 plant fiber):**
  - **Where:** at an inside corner (an L-shaped house), the two roofs' eaves both reach into the same 0.5 × 0.5 m square under the valley corner's low corner.
  - **Shape:** this piece fills that square cleanly. Its top follows the higher of the two eaves' slopes, folding along a valley down the diagonal, and a flat board underneath hides where the two eaves' fascia boards cross.

**Plots**

- **Chosen from a list** of available building types (house, forge, storehouse). Each type has requirements, such as workplace items or housing furniture, shown as a checklist. The building works only when they are met; extra decoration is up to the player.
- **Adjustable at any time:** plots can be resized and moved whenever the player likes. The building re-checks its requirements after every change and stops working (NPCs included) if something required ends up outside.
- **Overlap allowed:** plots can overlap so buildings can connect. Pieces may overlap too (see Overlapping).
- **Ownership:** every piece belongs to the plot it was placed in, even inside an overlap, and only its own pieces count toward its requirements.
- **Moving a building** takes only its own pieces. A gap left in a connected building is rebuilt by hand.
  - **Starting it:** with the hammer out, aim at a plot (its ground or one of its pieces; the controls row shows "Plot: move, resize… [E]"), press E for its panel, then Move plot (or M). In plot view E always opens the plot; outside it, a door, chest or the Storehouse's storage under the crosshair does its own thing first.
  - **Moving:** the plot and all of its own pieces (ghosts too) lift into a see-through preview that follows the crosshair, turning about its middle: the wheel 5° a notch, Alt + wheel 1°, R back to how it stood (and Page Up / Page Down raise and lower it: see below). Left-click puts it down; right-click or Esc cancels and puts it back. Pieces of other plots stay where they are, even joined to it.
  - **Raising and lowering:** Page Up / Page Down raise and lower the whole building (plot, pieces and furniture together): 0.25 m a press, 0.05 m with Alt, no limit either way; Backspace puts it back where it would sit (its middle on the ground). The panel shows "Turn 30° · Height +0.75 m". The height carries into where it's put down; settlers keep their jobs and beds, which move with it. Measured through the real plot placer: the Basic House (109 things) moved onto 33° ground and raised 0.75 m came down with its middle exactly 0.750 m above the ground (Backspace showed +0.00 m on the way), every piece, bed included, moved together to within 0.1 mm; the Forager's Hut (155 things) lowered 0.5 m came down exactly 0.500 m into the ground, every piece, basket and chest together to within 0.1 mm. Both kept their id and kept working.
  - **Nothing blocks it:** its pieces may overlap other buildings (pieces, furniture, workbenches, chests, campfires) and plot outlines, and sink into the ground as far as you like; anyone standing where it lands glides aside (see Overlapping). Steep ground is a yellow warning.
  - **After:** its id stays, so settlers keep their jobs and beds; corner posts, ridge logs and lips are worked out again, and settlers' paths follow.
  - **Measured** through the real plot placer, on the day-4 save: the Forager's Hut (155 things of its own) moved 10 m and turned 30° (6 wheel notches): every piece ended up offset and turned together (0.0 mm, 0.04° from exact), none of the 271 other plots' pieces moved, and it was still working afterwards. (Since then nothing refuses a move: the Basic House moved onto the Storehouse and 8° ground placed.)
- **Resizing:** in plot view (P), aim at a plot's edge or corner (it lights up; the controls row shows "Resize plot [Drag LMB]") and drag. The plot panel's hint says so.
- **Shrinking a plot:** pieces that would fall outside glow red. Confirming shows a warning, e.g. "6 pieces will be removed and refunded to your storage. Proceed?" (Proposed destination: warehouse, else nearest chest with room, else a crate dropped at the plot.)
- **Built so far (first version, T1):** the build menu's Buildings tab (formerly Plots) lists five plot types, each a `PlotType` file in `buildables/plots/` (requirements and smallest size are data; there's no largest): House (roofed, door, 1+ bed, campfire or fireplace; at least 6×6 m; houses one settler per bed), Forager's Hut (roofed, foraging basket, storage chest; 6×6; also gathers stone, copper and tin), Woodcutter's Hut (chopping block, tool rack, storage chest, roofed or not: no roof needed; 6×6), Storehouse (roofed, storehouse storage; no door needed; 8×8) and Workshop (roofed, workbench; 6×6). All unlock with the hammer and cost nothing. Drawing: click one corner on the ground and then the opposite corner; the rectangle stretches between them in 1 m steps with its size floating over it ("8 × 6 m"), red with the smallest size in its label (and it won't place) while it's too small. Before the first click, R turns the drawing direction 90° and Alt + wheel 15°, to line plots up with buildings. Right-click or Esc cancels. Once placed, a plot shows nothing in the world. Plot view (P with the hammer out, and on anyway while the build menu's Plots tab is open or a plot is being drawn, moved or resized) shows every plot's faint glowing outline on the ground, green while it's working and amber while it's missing requirements (no labels in the world). With the hammer out, a plot tracker on the right of the screen (a small plaque, vertically centred, fading in and out, hidden while a menu is open; every line wraps at a fixed width, and it's placed again whenever its size or the window changes, so it always stays wholly on screen) shows the plot you're standing in, or the one you aim at in plot view (up to 20 m): its name, type and capacity, "Working" in green or "Missing requirements" in amber, and its checklist ("✓ Bed 1/1", "✗ Door 0/1"). When a plot turns working, a message says so ("House is now working"). With the hammer out, E aimed at the ground or a piece inside a plot opens its panel (brass plaque; see Moving a building): editable name, type, size, capacity, a live checklist with ticks and crosses ("Roofed ✗ (Bed is not under a roof)"), "Working" or "Missing requirements", Move plot [M] and Remove plot, and a hint saying how to move and resize it. Resizing, in plot view: aim at an edge or corner (it lights up), hold left-click and drag; the outline follows in 1 m steps, never below the smallest size, owned pieces that would end up outside glow red, and letting go asks before taking them down for a refund to the inventory (overflow left in a bundle at your feet). Ownership: a piece, furniture item, workbench, chest or campfire placed with its middle inside a plot belongs to it (in an overlap, the plot whose middle is nearest the player). A new or enlarged plot also takes in unowned things inside it. "Roofed" means every required furniture item has the plot's own roof (or a floor above, as for shelter) straight over it. Move lifts the plot and its own pieces into a green preview (see Moving a building). Remove plot keeps its pieces standing, unowned. Requirements are checked again whenever something is placed, removed, moved or resized. Plots, names, sizes, turns and owners are saved (older saves keep their plots, even ones smaller than the new minimum). Code: `building/plots/` and `ui/plot_panel.gd`.
- **Chimneys:** a chimney section (6 stone, 2 sticks, 1 rope) and a chimney top (6 stone) in the Furniture tab, unlocked by building a fireplace; Meshy models fitted to the fireplace chimney's 0.41 m square (a section 1 m tall, the top 0.4 m), their tops and bottoms flattened so they stack cleanly. A section snaps onto the fireplace's chimney or another section, the top onto either, corner to corner (aim at the fireplace or the section below); Shift places them anywhere. Chimneys pass through roofs like any piece may overlap another. While the fireplace burns, soft light grey smoke (lit from behind as well as in front, so it never goes dark) rises from the top of its stack (the top, or the highest section), widening and fading, drifting a little with a light breeze. The fireplace burns a layered particle fire (orange licks round a yellow core, a few sparks) on logs in its hearth (`building/fire_effects.gd`), and its light is a soft warm amber, faint by day and brighter at night, flickering. Furniture, the workbench, chest and campfire standing in a room, and a chimney through its roof, don't break the "closed room" check.
- **Furniture models:** the chopping block, tool rack, storage shelf, fireplace, workbench, bed (the Rustic Bed: a full 2 m long and, at its own proportions, 1.34 m wide, turned so its headboard is at the back against the wall) and foraging basket (0.62 m across its rope handle) show Meshy models, each fitted evenly into the piece's solid box (sized to the model's proportions, so collision, placement and backing onto walls match what you see; the fireplace's own flames and light burn in its hearth). The stone sorting table shows its Meshy model too (a table with baskets and a sack round it), 1.6 m wide like the old placeholder, at its own proportions (0.83 m high, 1.23 m deep), with a plain box collision (1.26 m deep, to take in its baskets). Two woven baskets (the Woven Basket model, 0.38 m across) stand with it as part of the piece, as in its concept image: green herbs heaped in one at the front right corner, tangled plant fiber in one under the left end (just inside the left legs, as the model's own rail and clutter take the far end). They sit on floor the model leaves free (`PieceShapes.MODEL_EXTRAS`); its icon is cut from its concept image (fixed in the icon manifest). Build menu icons are rendered from the real pieces and models (see Build menu icons).
- **Storage furniture (Meshy models, Furniture tab):** each is fitted to its model's proportions, sits on the floor, and snaps and demolishes like other furniture.
  - **Storehouse Storage:** stacked chests and a sack with a pitchfork, 1.7 m across, simple box collision; 10 planks, 4 rope, 2 stone. The Storehouse's requirement, and its town storage (E opens it).
  - **Decoration only:** Firewood Rack (6 wood, 4 sticks, 1 rope), Stone Ore Bin (8 stone, 2 planks, 1 rope), Wooden Slat Crate (3 planks, 1 rope), Woven Crate (6 plant fiber, 3 sticks), Woven Basket (4 plant fiber, 1 stick). Storage shelves are decoration only now too.
  - **Icons:** these six use pictures cut from their concept images (background removed, cropped, square, 256 px), not renders. They're marked "fixed" in the icon manifest so the automatic re-render leaves them alone. The originals are in `assets/ui/hd/`.
- **Build menu icons:** every build icon is staged the same way by `IconStudio` (`building/icons/`). It uses an orthographic three-quarter view from the front right, a little above, with a warm key, a soft cool fill and a subtle rim light from behind, rendered at 512 px and saved at 256 px with clean edges.
  - **Building pieces** stand solid among faint, pale, see-through outlines of the neighbours they attach to, placed by the snap rules. For example: an eave on the low edge of a faint roof; a gable on a faint wall under a faint roof; a ridge cap on two roof halves; corners between faint roofs; a valley eave corner under the faint L of roofs and eaves; a door in a faint doorway; stairs up to a faint raised floor; a pillar or pole under a faint floor corner; a beam on two faint posts; ladders and railings on faint floors; small, half, long and short walls beside a faint 2 m wall; curved walls on round floors; the cone roof on a curved wall; chimney pieces on a faint fireplace.
  - **Scale:** every piece in a tab is drawn at one scale (the tab's largest fills about 75%), so a 1 m wall really is half as wide as a 2 m one. Roof pieces turn so you look onto their tops.
  - **Furniture, workbench, chest, campfire and lean-to** have no ghosts. Each fills its own icon (at one scale, a basket would be a speck beside a bed) and stands on a small faint floor patch.
  - **In the slot**, the build slot draws the soft dark vignette behind the (transparent) icon, smooths it down with mipmaps and puts a small brass corner badge over it where size or angle tells pieces apart ("2×2", "1×1", "2 m", "1 m", "2.83 m", "26°", "45°", "22.5°"). A locked piece's dark silhouette keeps its shape.
  - **Re-rendering:** while working on the game (debug runs from the project, never in an export), the title screen quietly redraws any icon whose piece changed. Each icon's fingerprint in `assets/icons/build/icon_manifest.json` covers its buildable file and what that loads, its model folder, the piece-shaping and drawing code, and the studio. The console's `icons` (or `icons all`) does the same on demand. New pictures show at once; the editor picks up the files when it next gets focus.
  - **Template pictures** are the whole building from a front three-quarter view in low golden-hour sun (warm key, cool sky fill, rim from behind), tightly framed (`building/templates/template_thumbnail.gd`). Pictures older than that code are redrawn the same way.
  - **Inventory item icons** each fill their square and carry a soft drop shadow (coal, being dark, gets a soft pale glow). The three ores have their own rock colours (blue-grey tin with white flecks, tan copper with teal, dark iron with red), scrap is a warmer metal than stone, and the torch's head glows orange so it isn't mistaken for the spear.
- **Furniture (first version):** the Furniture tab holds simple placeholder furniture that counts toward plot requirements by name: bed (6 planks, 4 plant fiber), foraging basket (4 plant fiber, 2 sticks), chopping block (2 wood), tool rack (3 planks, 2 sticks), stone sorting table (4 planks, 2 stone), storage shelf (4 planks) and fireplace (6 stone), plus the campfire, workbench and storage chest. The new pieces unlock with the first planks, demolish for a full refund and save. Furniture (and the workbench, chest and campfire) stands on whatever floor, foundation or ground is under the crosshair; snapping (Shift not held), it sits on a 0.5 m grid in the floor's own frame, turned by the wheel from the floor's facing, and the bed, shelf, tool rack and workbench back up flush against a wall they're close to. Like pieces, it may overlap anything. The fireplace burns without fuel and warms like a campfire (6 m), so inside a closed house it keeps you warm.

**Templates**

- **Build it yourself or use a template.** A placed template becomes ordinary pieces the player can change.
- **Placing:** the template shows fully built with real textures, plus a green outline glow (yellow for steep ground; nothing makes it red).
- **Confirming:** it turns into blue ghost outlines that show each piece's cost, plus overall progress (e.g. "Forge: 14/32 pieces").
- **Filling:** the player hits a ghost piece with the hammer while carrying its materials. Building uses only what is in the player's inventory, not storage. Ghost pieces can be removed or swapped for free before they are built.
- **Player templates:** players save their own builds as templates.
- **Built so far (first version):**
  - **Saving:** the plot panel's Save as template saves every piece, furniture item, workbench, chest and campfire the plot owns, ghosts included. That's each one's type and its position, turn and height relative to the plot, plus the plot's type and size, under a name the player types. A picture of the building is rendered with it.
  - **Where templates live:** each template is a JSON file with its picture (.png) beside it. Built-in templates are in the project (`buildables/templates/`) and marked "Built-in" in the menu; the player's own are in the user folder (`user://templates/`, marked "Yours"). In debug builds the save dialog has "Save as built-in", which writes into the project: that's how the T1 templates are made. Code: `building/templates/`.
  - **Buildings tab:** the build menu's Plots tab is now the Buildings tab. It has a row for each plot type, listing its templates (picture, built-in or yours, piece count, total material cost), then "Empty plot", which draws a plot as before. Templates unlock with their plot type.
  - **Renaming and deleting templates:** right-clicking a template, or clicking the small ✕ on its picture while hovering, offers Rename and Delete (`ui/template_actions.gd`).
    - Delete asks "Delete the template X?" and removes its file and picture.
    - Rename asks for the new name, refusing a name another template already uses. It rewrites the file with the new name and renames the file and picture to match.
    - Esc steps back.
    - The player's own templates can always be changed. Built-in ones only in debug builds, where it edits the files in `buildables/templates/`; never in a release build, where the ✕ doesn't show and right-clicking says they can't be changed.
    - Plots and buildings already placed from a template don't depend on its file, so deleting or renaming it leaves them as they are.
  - **Placing:** the whole building follows the crosshair, fully built with its real look and a soft outline glow, with its plot's outline on the ground.
    - It glows green; never red (it's laid out as ghosts, which nobody can be in the way of, and it may overlap anything); yellow (a warning, still placeable) where the ground under its foundations is steeper than 30° or it would stand in water. Pieces that exactly repeat ones already there are left out.
    - R turns it 90° and Alt + wheel 15°; Page Up / Page Down raise and lower it (Alt: finely); Backspace resets the turn and height.
    - Near another building it snaps where one of its outer snap points meets one of theirs, by the usual snap rules at its current turn.
    - Left-click creates the plot (the template's type and size, adjustable afterwards in plot view) with everything in it as a ghost. Placing costs nothing.
  - **Ghosts:** each ghost shows its simplified look (the ghost under the crosshair its full detailed look: every plank, shake and rafter; furniture and the workbench, chest and campfire their models) in a soft see-through neutral grey (#9a9a9a, about 30% opaque), slightly lighter and stronger toward the edges where a surface turns away from you. The ghost under the crosshair (the one you'd fill) brightens a little. Code: `building/templates/ghost_look.gdshader` and `BuildPiece.set_ghost`.
    - **Rules:** ghosts aren't solid (the player, settlers and every physics check pass through them), and don't count as built for requirements, shelter, settlers, joint details or fires.
    - **Aiming:** aim at a ghost with the hammer and it brightens, and the placement panel shows its name and cost (red if you're short).
    - **Building:** left-click builds it from your inventory only, turning it into the real piece, workbench, chest or campfire (anyone standing in it glides aside).
    - **Holding:** holding left-click keeps going, about 4 a second, with the ghost under the crosshair and then the nearest ghosts of the same plot joined to what's been built this hold, until materials run out.
    - **Removing:** middle-click removes a ghost for free.
    - **Alongside:** normal pieces can still be placed in the plot alongside ghosts. Removing a plot removes its ghosts; moving or resizing it takes them along.
    - **Tracker:** while a plot has ghosts, its tracker says "Under construction" and shows "Building: 14/28 pieces", then each material needed, carried and missing.
    - **Finishing:** when the last ghost is built: "House is finished!", and the usual requirement checks take over.
  - **Saved:** ghosts save and load with their plot (ghost pieces as a flag on the piece, ghost buildings with the buildings).

**Storage and builders**

- **Chests:** the player's personal storage. NPCs never touch the player’s personal chests (those outside any plot); chests inside plots are settlement storage.
- **Warehouse:** town storage the player can open. NPCs drop their daily output here.
- **Built so far (town storage, first version):** the Storehouse is the warehouse. Code: `building/plots/town_storage.gd` (data: `PlotType.town_storage_item` and `town_storage_slots`).
  - **Size:** a working Storehouse (one with its Storehouse Storage) gives 60 slots (a slot holds any amount of one item, as in a chest), and each extra Storehouse adds 60 to the shared pool, the town storage. Storage shelves are decoration only.
  - **Tracker:** a Storehouse's tracker shows "Town storage: 14/24 slots" for the whole pool, or "closed until it's working".
  - **Opening it:** E on the Storehouse Storage in a working Storehouse ("Open town storage") opens the Town Storage screen beside your inventory, in the chest screen's style:
    - the whole pool, sorted by category (food, materials, tools, other), with the slots in use in the title and each category's total;
    - drag or shift-click to move stacks across;
    - Deposit resources moves every material and food item from your inventory into it, leaving tools and the action bar alone.
    - It scrolls past three rows. A shelf in a Storehouse that isn't working says so.
  - **Settlers:** job output at dawn goes into town storage while it has room, otherwise into the hut's own chest. What fits in neither is lost: "Forager's Hut: Town storage full (3 herbs lost)". Settlers eat from town storage first, then from plot chests as before, and a House's "Food stored" counts it.
  - **Refunds:** shrinking a plot refunds its removed pieces into town storage first, then your inventory, then a bundle at your feet. Demolishing by hand still refunds to your inventory. Building (placing pieces, filling ghosts) still takes only what you carry.
  - **Saved:** with the Storehouse plots, each holding a share of the pool.
  - **Shrinking, so nothing is lost:**
    - A Storehouse that stops working (missing requirements) keeps its share. This includes older Storehouses built before Storehouse Storage existed, which show "Missing requirements" until it's built. The pool then holds more than its room and takes no new kinds of item (and no new stock at all while no Storehouse works) until there's room again. Settlers can still eat the food in it.
    - Only removing a Storehouse pushes stock out: whatever the remaining Storehouses couldn't hold drops in a bundle where it stood, with a message.
- **Granary (later):** a separate food store with spoilage.
- **Builder NPCs** fill ghost pieces from warehouse stock. First version: materials come straight from the warehouse. Later, once NPCs can walk around the town, builders carry loads from the warehouse to the site.

## World and look

The valley is built from real-world elevation data and is heading toward a realistic natural look, with steampunk ruins layered on top.

- **Terrain:** a heightmap of rolling hills in the English Midlands (36 to 226 m real elevation), built in chunks. Currently 1500 m across with the hills exaggerated. The rest of the heightmap is room to expand, and airship travel can open new regions later.
- **Water:** a single water level fills the low ground, forming the river and lake.
- **Visual target:** a realistic forest-and-stream look like the reference screenshot (rocky slopes, ferns, deer). Lighting, fog, shaders, and procedural grass come first; real art assets (Poly Haven, ambientCG, asset packs) replace placeholders in a later beauty pass.
- **Places to discover:** the ruined airship dock, an abandoned workshop, and rusting machinery in the hills.
- **Campsites:** abandoned refugee camps spawn at random around the map, with new ones appearing over time in unexplored areas.
  - They hold schematic fragments, loot and journal pages, and later dangers (wolves, then Hollows).
  - They're also how settlers arrive: some have a refugee who joins if there's a free bed.
  - The current morning arrivals are temporary until campsites exist.
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

- First-person movement, mouse look, and jumping; hold Shift to sprint (1.7× walking speed, forward and diagonally forward only, started on the ground; a running jump keeps its speed; the view widens slightly; hunger drains 1.5× as fast; costs stamina, see Threats); you step up onto ledges up to 0.45 m (floors on the ground, low foundations, stair steps) and down off them without a hop, the camera easing through each step, while taller edges, walls and steep ground still need stairs or a jump (the body is a cylinder 0.8 m across and 2 m tall)
- Day/night cycle with warm sunsets and dark nights
- Real-world heightmap terrain in chunks, with water filling the low ground
- Visual pass: slope-based ground coloring, grass, rocks, improved trees, water shader, haze
- Gathering scrap, coal, and berries with E, with an on-screen counter
- Tree chopping: 4 hits, the tree falls, a stump remains, +3 wood
- Hunger and stamina meters (warmth is switched off for now; see Threats); eat berries with F; build a campfire with B for 3 wood
- Inventory screen on Tab with 20 slots
- Free building with snapping wooden pieces, square and round, furniture, and T1 plots that turn buildings into working ones (see Building system)
- Settlers: refugees arrive for free beds, live in Houses, work at the three gatherer huts, and follow a daily routine (see Settlement and defense)
- Title screen (`ui/title_screen.gd`, `ui/title_background.gd`):
  - **Background:** the painting (`assets/ui/title_background.jpg`: the refugee on a ridge, the cabin, the crashed airship, the ruined capital) always covers the screen, cropping a little on screens that aren't 16:9 (and shifting on narrow ones so the refugee stays clear of the menu).
  - **Drift:** it zooms in about 6% around the refugee and pans slightly over 60 seconds, then eases back, looping.
  - **Living details:** understated smoke from the cabin chimney and the airship wreck, a fog band drifting across the valley, the cabin window flickering warmly, and the castle's golden glow pulsing faintly.
  - **Menu:** a soft dark gradient down the left edge sits behind a narrow menu panel in the ornate frame. It holds the title, then Continue (the latest save, with its world, day and date small beneath; greyed out with no saves), Load Game, New Game, Multiplayer (greyed out, "Coming soon" on hover), Settings and Quit Game (asks Yes/No).
  - **Controls:** the mouse, keyboard and controller all work (Up/Down, Enter, Esc). The lit button glows warm. The version (`application/config/version`) shows bottom right.
  - **No saves:** the title screen now always shows, instead of jumping straight into a new game when there are no saves.
- Settings (`ui/settings_panel.gd`, `ui/game_settings.gd`), from the title screen or the pause menu:
  - **Options:** master, music and effects volume (the Music and Effects buses are made if missing); window mode (windowed, fullscreen, borderless); resolution (windowed only); V-Sync; render scale (50–100%, default 100%: the 3D world is drawn at that share of the resolution and scaled back up with AMD FSR, the HUD and menus staying sharp); mouse sensitivity; invert Y; field of view (sprinting still widens it).
  - **Saving:** changes apply at once and are saved to `user://settings.cfg`.
- Drawing cost (what keeps building areas fast):
  - **Shared looks:** each piece type's close-up look is made in 4 versions, picked by the piece's id, and pieces of the same version share one mesh, so Godot draws them together. Each piece's own slight colour comes from the shader. Corner posts, ridge logs and foundation lips share a few versions per size the same way.
  - **Three looks by distance:** the full rustic look within 15 m; a simplified version (the same planks, logs and stones with plain edges, each row of shakes as one strip, fewer-sided logs, no rope) out to 40 m; the plain textured box beyond. Each fades into the next over 2 m (Godot visibility ranges).
  - **Shadows:** pieces cast their shadow with the plain box, or with the simplified look where that's lighter (foundations), never with the full detail. Foundation lips and hearth logs cast none.
  - **Ghosts and previews:** template previews and ghost pieces show the simplified look; only the ghost under the crosshair shows full detail.
  - **Fireplace light:** its shadow leaves out grass, ferns and scattered rocks (render layer 2), stops 20 m away, and the light fades out from 40 m.
  - **Scattered rocks:** drawn in one batch per 128 m square of map, so only the squares in view (and near enough for shadows) are drawn.
  - Merging a finished plot's pieces into combined meshes was looked at and left out. Draw calls aren't what limits the frame rate (around 450 to 550 visible in the settlement, with the 404 pieces taking about 140), and merging would undo the shared meshes and per-piece distance looks.
  - **Measured** (Nov 2026, the day-4 settlement, 2083×1080): triangles drawn per frame fell from 9.9 million (7.8 million of them shadows: the fireplace light's shadow about 3.9 million, the rocks drawn whole into every shadow pass most of the rest) to 3.4 million (1.5 million shadows). The frame rate there was about the same (84 before, 77 to 93 after, depending on the view): at that size the graphics card is limited by pixels (grass), not triangles. Render scale is the setting for very high resolutions.
- Short freezes (what keeps the game from hitching):
  - **Grass and ferns:** each 32 m patch is worked out on a worker thread from a snapshot of what it needs (ground, clear zones, buildings), and finished patches are swapped in one per frame. A new floor or plot hides the plants under it straight away by flattening those instances in the stored patch, instead of regrowing the whole patch; removing one marks its patches to be regrown in the background.
  - **Saving:** the save's data is gathered on the main thread (a deep copy); turning it into text, writing the file, shrinking the picture and clearing away old autosaves happen on a worker thread. Manual saves wait for it to finish (the save list shows them straight after); quitting and the next save wait for any save still being written.
  - **Shader warm-up** (`building/pieces/shader_warmup.gd`): when a world opens, every building look (plain, close-up and simplified looks, their shadows, the distance fade, the template glow overlay, the grey and targeted ghosts, the placing preview and the take-down glow) is drawn once for a few frames under a dark "Getting the valley ready…" cover, so the graphics card compiles those shaders then and not the first time you preview a template.
  - **Template preview:** its look is built about 100 nodes a frame and shown once it's all there ("Setting out the preview…" in the panel meanwhile; clicking before then finishes it at once). Its outer snap points are found with a 5 cm grid and kept per template. The snap search only looks at sockets the template wants, sorted into a 1 m grid; the physics check of where it stands runs every other frame (every frame or so while it's moving) once the look is complete. The shader warm-up also draws the preview's glow over fading looks, ghosts while fading, the plot outline and its floating label, and every workbench, chest and campfire templates hold.
  - **Laying out a template:** its ghosts go into the world 12 a frame; once they're all in, the plot takes in what stands inside it and its checklist is checked. Corner posts and ridge logs are rebuilt once, 0.2 s after the last piece goes in. Measured with the spike logger: no frame over 33 ms while laying one out (before: two of 34 and 35 ms, mostly those rebuilds).
  - **Respawns:** at most 6 things come back per check; when more are due (after a long sleep) the next check follows a tenth of a second later.
  - **Spike logger** (debug builds only, `dev/spike_log.gd`; Settings → Debug → "Log lag spikes", off by default): every frame over 33 ms prints a `[Spike]` line with the frame time, what the player was doing, the time spent in each timed system that frame (building, detail looks, saving, respawns, settlers and navigation, day and night, grass, plot checklists, menus), the nodes added and the shader pipelines compiled for the first time. Under it, the nodes added that frame and the one before (a node is first drawn, and its shaders compiled, in the render that falls in the next frame's time), by name and parent ("Detail (MeshInstance3D) ← Wall ×12"), and with shaders compiled, the kinds compiled (mesh, surface, canvas…) and the materials those nodes carry (Godot counts compiles but doesn't say which material each was for; "none" means something already there was drawn a new way). Systems are timed with `SpikeLog.begin()` / `SpikeLog.end(name, started)`.
  - **Measured** (Nov 2026, the day-4 settlement, one scripted run: placing and taking down pieces, a template, walking, the inventory and build menu, an autosave, a dawn): 32 spikes before (longest 1095 ms, average 325 ms; nearly all regrowing grass, 700–850 ms each time a piece was placed or removed, and the template preview's snap search) and 5 after (longest 181 ms, average 84 ms, all while choosing and laying out a template). After spreading the template's preview and laying out over frames, the template part alone went from those 5 to 2 (34 and 35 ms, while its ghosts go in, mostly the corner posts and ridge logs being rebuilt each frame).
- Developer console (debug builds only, never in a release build; `dev/`):
  - **Opening:** ~ opens and closes a brass plaque across the top of the screen, with a monospace scrolling log, an input line, history on Up/Down, and Tab completing command and item names. While it's open the player stands still and other keys are ignored.
  - **Commands:** help, give <item> [amount], give_all [amount], freebuild, unlock_all, god, fly, time <0–24>, day, spawn_settler [count], tp <x> <z> / tp settlement, clear_inventory, save, load. Unknown commands and bad arguments print the right usage.
  - **Toggles:** freebuild (pieces, furniture, buildings, ghosts and crafting cost nothing and refund nothing), god (hunger and stamina never drop) and fly (Space up, Ctrl down, Shift faster, through everything). They aren't saved and start off every time a world opens. A "DEV" tag in the top-right corner names the ones that are on.
  - **Shortcuts:** F9 runs spawn_settler and F10 runs day.
- Compact steampunk-brass HUD, laid out at 1920 × 1080 and scaling with the window (same look at 1080p and 4K): the brass vitals panel bottom left (`assets/ui/vitals_panel.png`: a half-gauge whose needle shows stamina, red zone at full, over hunger and stamina channels that fill gold and blue-green with soft ends, labelled "Hunger" with a steak and "Stamina" with a lightning bolt), the brass compass with its small clock mounted on the action bar's left end (the bar's own left scrollwork is trimmed off), drawn on top, its brass right up to slot 1's frame and its loose side curls tucked under it (`compass_clock.png`: a needle pointing north relative to where you face, hour and minute hands showing the in-game time), a thin brass ring crosshair, what E would do with the thing you aim at in a line under the crosshair, and a centred row of the controls that apply right now just above the action bar (label and key badge pairs; "Eat Berries [F]" while carrying berries, "Demolish [MMB / Hold X]" and "Plot view [P]" with the hammer out), with a small panel above it while building or demolishing (piece icon, name, cost or refund, one line of details). The action bar is the brass bar art (`action_bar.png`) with a slot picture over each opening: a plain slot when it holds something, a gear slot when empty, and a gold, glowing slot for the selected one. Menus are drawn 1.5× (`MenuStyle.MENU_SCALE`). The blank brass plaque (`plaque.png`, 9-sliced just inside its corner rivets, edges stretched) frames the build placement panel, build menu, inventory, crafting and pause menus; the title screen alone uses the ornate `panel_frame.png`. Buttons, slots and key badges keep a restrained code-drawn brass style (`ui/brass_style.gd`: thin bevelled worn-gold borders, recessed slots, a faint gear in empty inventory slots). Anything missing from `assets/ui/` is drawn in code

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
7. Settlers and jobs (in: arrivals, homes, jobs, daily routine, job output and food; next: crafting buildings with NPC workers, then the opening quests, tech tree and campsites)
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
