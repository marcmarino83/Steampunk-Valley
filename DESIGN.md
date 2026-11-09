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
  - **Walking:** Godot navigation, baked at runtime in 32 m tiles around every plot (64 m to spare) and every settler, from the valley's heights (water left out) and the solid shapes on them (pieces, furniture, the workbench, chests, campfires, trees, rocks). Doors are left out, so settlers path through doorways. Once a second each tile's pieces are compared with when it was baked; a tile where something was placed, demolished or moved is baked again, one tile per frame. Settlers step up low ledges (floors on the ground, thresholds up to 0.5 m), open closed doors as they reach them (doors never block them), and close the ones they opened behind them.
  - **Talking:** E aimed at a settler opens their panel (brass plaque): name, home, job, status ("Working at Forager's Hut", "Walking to…", "Heading home", "Sleeping", "Idle: no job", "Can't work: missing roof"), with Assign home and Assign job, each listing the working plots with a free place (plus No home or No job).
  - **Homes and jobs:** a House holds one settler per bed, each sleeping in a bed of their own (beds in the order they were built, residents in the order they arrived). The Forager's, Woodcutter's and Stone Gatherer's Huts take 1 worker each (`PlotType.workers`, standing at `PlotType.work_at`: the foraging basket, chopping block or stone sorting table); the Workshop and Storehouse come later. The plot panel lists a House's residents and a workplace's worker (with Unassign); the plot tracker has a line for them too.
  - **Daily routine (the sun's clock):** from 0.28 to 0.70 they work, bent over their workplace's furniture, now and then wandering a little inside the plot; in the evening they go home and idle there; from 0.78 to dawn they sleep in their bed. With no job they idle around their home; with no home they sleep by the nearest campfire or fireplace (or where they stand). A workplace that stops working leaves its worker idling there, showing "Can't work: reason".
  - **Daily output (at dawn, 0.27 on the sun's clock):** each working workplace with a worker makes its day's amount into town storage (the working Storehouses; see Storage and builders) while it has room, otherwise into its own storage chest.
    - Forager's Hut: 20 items a day, shared out by sliders.
    - Woodcutter's Hut: 12 wood and 8 sticks.
    - Stone Gatherer's Hut: 15 stone.
    - A hungry worker makes half.
    - What won't fit in either (no free slot for a new kind of item; slots hold any amount) is lost, with a message: "Forager's Hut: Town storage full (3 herbs lost)" ("chest full" with no working Storehouse).
    - All three workplaces require a storage chest of their own, so a working one always has somewhere for its output. Should one somehow have none, the day's output is lost, with a message.
    - The amounts are data on each plot type (`daily_output`, `split_output_total`, `split_output`).
  - **Forager sliders:** a Production section in the Forager's Hut plot panel has sliders for berries, herbs, mushrooms and plant fiber, always adding up to 100%. Moving one shares the rest among the others in their current proportions. Each shows the resulting amount per day. The default is 50/20/20/10 (10 berries, 4 herbs, 4 mushrooms, 2 plant fiber), saved with the plot. The other workplaces' Production section lists their fixed output.
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
- **Snap pieces:** foundations, walls, floors, roof sections, stairs and doors that snap to each other.
- **Round builds:** curved wall arcs (22.5° and 45°) that close into full circles, round tower kits (circular floors, cone roofs, spiral stairs), and 15° rotation steps with a hold-key for free rotation.
- **Not voxels:** Enshrouded-style smooth voxel building was ruled out as too big for a first project, and it would not fit the existing terrain.
- **Built so far (first version):** wooden pieces in the hammer's build menu, under tabs (Foundations, Floors, Walls, Roofs, Beams & Pillars, Stairs & Doors, Round, Other; Q and E change tab). Square pieces (2 m grid, 1 m half step): wood and stone foundations (solid blocks 3 m tall that go 2 m into the ground, stacking and snapping side by side; floors, walls and stairs snap onto their tops like onto floors), floor, wall (2.5 m high), doorway wall (opening 1.2 m wide and 2.2 m tall, so you walk through with the door open), door (E opens and closes it), window wall, 26° roof (rises 1 m over 2 m), stairs, and wood and stone pillars (on floor and foundation corners and edge middles, stacking; floors, walls and roofs sit on their tops, for platforms and porches). Triangles combine with the squares: a right triangle (half a square, long side 2.83 m) and a 45° triangle (two 2 m sides at 45°, short side 1.53 m, filling the gap between squares turned 45°, so squares and triangles make an octagon), each as a floor and a wood and stone foundation, with long (2.83 m) and short (1.53 m) walls for their odd sides. *Round* (one ring, radius 2.61 m, so a 45° arc spans 2 m and eight close a circle 5.2 m across): wood and stone round foundation wedges, curved walls (45° and 22.5°), round floor wedges and cone roof wedges (eighths), and 22.5° round floor and foundation wedges (sixteenths) to match the 22.5° walls. A round wedge's curved edge lies exactly under the curved walls' middle line. Every piece unlocks with the first planks. Pieces snap (dots show the snap points; while snapped, R turns a square piece (square and 1×1 floors, foundations) 90° about its own middle, so it stays exactly where it snapped and only its planks change direction; a square floor or foundation snapped beside another one starts with that one's plank direction, so it usually needs no turning. Any other piece keeps the same snap point attached and stays on the same side of it: R steps through the ways it really fits there (a triangle meeting the edge by each of its sides, a beam's directions round a corner), and does nothing where there's only one way (a wall on a floor edge looks the same either way round; a curved wall on its ring). Alt + wheel turns in 15° steps (square pieces about their middle, others about the snap point). The turn stays until a different piece is picked); otherwise they go wherever the crosshair is, on the ground or on other pieces, and may float: R turns 15° and Alt + wheel turns smoothly. Page Up / Page Down or Ctrl + wheel raise and lower any piece, snapped or free, in 0.25 m steps (0.05 m with Alt), shown in the panel ("Snapped · +0.50 m") and kept for the next piece of the same kind until Backspace. Z turns snapping on or off for every piece until pressed again (shown in the panel); it's the only snapping toggle (Shift is sprint). Tab while placing opens the build menu: picking something switches to it, keeping the height and turn where they still apply, and closing it goes back to what you were placing. Stairs: the bottom snaps to floor and foundation edges (or stands on the ground), the top to an edge a level up, and stairs chain end to end; aiming at an edge above your eyes brings the stairs down to you by their top, an edge below takes their bottom. Pieces may overlap anything (see Overlapping, below). Demolishing is direct: with the hammer out, placing or not, pressing the middle mouse button on a piece makes it glow red, and letting go removes it for a full refund with a short message ("Demolished Wall (+4 Planks)"); looking off it before letting go cancels, and placing carries on afterwards with the same piece, height and turn. Holding X on a piece does the same for mice without a middle button (it glows red with a percentage while held; letting go early cancels). Nothing glows or gets removed otherwise. What won't fit in a full backpack is left in a bundle on the ground, picked up with E. Under a roof counts as shelter; a closed room (floor, walls, roof, door shut) stops the cold entirely, round rooms included. Floors and foundations keep the grass out. No structural support yet. Shapes and snap rules: `building/pieces/piece_shapes.gd`; each piece is a `PieceBuildable` in `buildables/structure/` or `buildables/round/`, and can show a real model instead of the plain shape (`model_scene`). Wood pieces are textured with Poly Haven's Wood Planks Dirt and stone pieces with Rock Wall 13 (2K copies; 4K originals in `assets/textures/hd/`, outside git), mapped at real-world scale (one copy covers 2 m) in a frame that follows the building, so planks run on across neighbouring pieces without seams: level on walls, along floors, down the slope on roofs and overhangs, round the curve on curved walls and round floors, along beams and up posts (`building/pieces/piece_surface.gdshader`). Each piece gets a slight colour and brightness of its own, and darker grime toward its edges and the foot of upright faces. That plain textured box is now only the distance version (beyond 60 m). Close up, every piece is built in code from real parts in warm weathered grey-brown timber (around #7d705f; the wood texture's light blotches flattened, its dark grain kept, each plank's narrow sides and bevelled edges darkened), tan-grey stone (around #8a8272, dirtier lower down) and thick brown hemp rope (around #8b6f47) (`building/pieces/piece_detail.gd`, `piece_detail.gdshader`): walls of separate bevelled horizontal planks (random thickness, height, tilt, ends and gaps) over a dark core, chunky plank frames round doorways and windows, a door of vertical planks with iron strap hinges and a rope pull, gables of planks with a king post and brace, floors of rough planks with gaps, wood foundations of stacked logs, stone foundations and pillars of irregular bevelled blocks with dark mortar, stairs of plank treads on log stringers, and roofs, corners, eaves and overhangs of decking under overlapping rows of split shakes (a few out of place), with rafter tails under the eaves and fascia and barge boards round overhangs. Each shape has 8 versions, picked by the piece's id, so a piece looks the same after loading and neighbours differ. Log corner posts with rope lashings stand wherever walls meet at an angle, a log with rope ties runs along every ridge where two roofs meet (unless a ridge cap is there), and every foundation edge not shared with another foundation gets a lip of stone (or logs) reaching 12 cm past it, so walls sit on top with stone showing; all three are worked out from the pieces as they change and aren't saved (`building/pieces/joint_details.gd`). Pieces keep their exact size, snap points and collision. Furniture keeps its own look. Every piece has an id and an owner plot, listed in the `PieceRegistry`, which also saves them.
- **The small kit (Valheim-style):** a 1×1 m floor; 1 m walls, half-height walls (2 m and 1 m wide, 1.25 m high) and a 1×1 m quarter wall, which snap to the 1 m points on floor edges and wall tops; gables (wall triangles) for the 26° and 45° roofs, standing on the wall under a roof end; a 45° roof, and for each pitch an inner corner (valley), outer corner (hip) and ridge cap, which snap onto roofs of their own pitch; beams (1 m, 2 m, and diagonals at 26° and 45°) and poles (1 m, 2 m), which snap end to end, to floor corners and edge middles, to wall-top corners and middles, along wall tops, and to each other; a 2 m ladder (hold W while facing it to climb); railings (2 m, 1 m) and a 2 m fence that chain end to end. Roof panels have both ends cut plumb, so two roofs snapped back to back meet in a sharp, closed peak (the ridge cap still sits over it) and the eave end reads as a cut rafter end; existing roofs pick this up when loaded. Overhangs, for each pitch (Roofs tab): an eave (2 m wide, 0.5 m out, carrying the roof's slope on outward and down; 1 plank, 1 plant fiber) on any roof's or hip corner's low edge, a gable overhang (0.5 m wide, 2 m along the slope; 1 plank, 1 plant fiber) on any roof's side edge, past the gable wall, and an eave corner (0.5 × 0.5 m; 1 plank) under a gable overhang's low end where it meets the eaves. Eaves and corners chain along a row, gable overhangs up the slope and back to back at the ridge. They match the roof's thickness and plumb cuts, have a fascia board along their outer edges, tuck over wall tops and gables, and don't count as roof for shelter.

- **Wall tops and roofs:**
  - **Top points:** the top edge of every straight wall piece has top points at both ends and every 1 m out from its middle, on its centre line. That covers the wall, doorway and window walls, the 1 m, half and quarter walls, and the short and long walls. Gables, walls and small walls stack on them either way round, so a gable stands on two quarter walls where they meet.
- **Overlapping (Valheim-style freedom):**
  - **What may overlap:** pieces, furniture, the workbench, chest and campfire, moved plots and placed templates may overlap anything: other pieces, furniture, plots, terrain, trees and rocks, with snapping on or off.
  - **Only two things block (red):**
    - You or a settler would be inside it: "You're in the way" or "Someone's in the way".
    - An identical piece is already there, within 5 cm and 5° (allowing for the shape's symmetry, ghosts included): "Already placed".
  - **Templates:** pieces that would exactly repeat ones already there (a wall shared with the building beside it) are left out when the template is placed.
  - **Warnings (yellow, still placeable):** steep ground under a template's foundations or under a moved plot, and steep ground or water under a workbench, chest or campfire.
  - **Physics:** placed pieces are still solid to walk into, and settlers still path round them.
  - **No flicker:** each piece's look sits up to 2.5 mm off its true place, in a direction of its own (from its id), so faces of overlapping pieces that lie in the same plane don't flicker.
  - **Old rules gone:** the old rules (the roof tolerance, chimneys passing through roofs, slender pieces and overhangs only bumping each other, rocks in the way) went with the overlap check. Furniture still backs up against walls.
- **Valley eave corner (each pitch, Roofs tab; 1 plank, 1 plant fiber):**
  - **Where:** at an inside corner (an L-shaped house), the two roofs' eaves both reach into the same 0.5 × 0.5 m square under the valley corner's low corner.
  - **Shape:** this piece snaps there and fills that square cleanly. Its top follows the higher of the two eaves' slopes, folding along a valley down the diagonal, and a flat board underneath hides where the two eaves' fascia boards cross.

**Plots**

- **Chosen from a list** of available building types (house, forge, storehouse). Each type has requirements, such as workplace items or housing furniture, shown as a checklist. The building works only when they are met; extra decoration is up to the player.
- **Adjustable at any time:** plots can be resized and moved whenever the player likes. The building re-checks its requirements after every change and stops working (NPCs included) if something required ends up outside.
- **Overlap allowed:** plots can overlap so buildings can connect. Pieces may overlap too (see Overlapping).
- **Ownership:** every piece belongs to the plot it was placed in, even inside an overlap, and only its own pieces count toward its requirements.
- **Moving a building** takes only its own pieces. A gap left in a connected building is rebuilt by hand. (Proposed: the new spot is checked for slope, and the ground is flattened or the move is blocked.)
- **Shrinking a plot:** pieces that would fall outside glow red. Confirming shows a warning, e.g. "6 pieces will be removed and refunded to your storage. Proceed?" (Proposed destination: warehouse, else nearest chest with room, else a crate dropped at the plot.)
- **Built so far (first version, T1):** the build menu's Buildings tab (formerly Plots) lists six plot types, each a `PlotType` file in `buildables/plots/` (requirements and smallest size are data; there's no largest): House (roofed, door, 1+ bed, campfire or fireplace; at least 6×6 m; houses one settler per bed), Forager's Hut (roofed, foraging basket, storage chest; 6×6), Woodcutter's Hut (roofed, chopping block, tool rack, storage chest; 6×6), Stone Gatherer's Hut (roofed, stone sorting table, tool rack, storage chest; 6×6), Storehouse (roofed, door, 2+ storage shelves; 8×8) and Workshop (roofed, workbench; 6×6). All unlock with the hammer and cost nothing. Drawing: click one corner on the ground and then the opposite corner; the rectangle stretches between them in 1 m steps with its size floating over it ("8 × 6 m"), red with the smallest size in its label (and it won't place) while it's too small. Before the first click, R turns the drawing direction 90° and Alt + wheel 15°, to line plots up with buildings. Right-click or Esc cancels. Once placed, a plot shows nothing in the world. Plot view (P with the hammer out, and on anyway while the build menu's Plots tab is open or a plot is being drawn, moved or resized) shows every plot's faint glowing outline on the ground, green while it's working and amber while it's missing requirements (no labels in the world). With the hammer out, a plot tracker on the right of the screen (a small plaque, vertically centred, fading in and out, hidden while a menu is open; every line wraps at a fixed width, and it's placed again whenever its size or the window changes, so it always stays wholly on screen) shows the plot you're standing in, or the one you aim at in plot view (up to 20 m): its name, type and capacity, "Working" in green or "Missing requirements" in amber, and its checklist ("✓ Bed 1/1", "✗ Door 0/1"). When a plot turns working, a message says so ("House is now working"). In plot view, E aimed at the ground or a piece inside a plot opens its panel (brass plaque): editable name, type, size, capacity, a live checklist with ticks and crosses ("Roofed ✗ (Bed is not under a roof)"), "Working" or "Missing requirements", Move and Remove plot. Resizing, in plot view: aim at an edge or corner (it lights up), hold left-click and drag; the outline follows in 1 m steps, never below the smallest size, owned pieces that would end up outside glow red, and letting go asks before taking them down for a refund to the inventory (overflow left in a bundle at your feet). Ownership: a piece, furniture item, workbench, chest or campfire placed with its middle inside a plot belongs to it (in an overlap, the plot whose middle is nearest the player); the placement panel always says "Building for: name". A new or enlarged plot also takes in unowned things inside it. "Roofed" means every required furniture item has the plot's own roof (or a floor above, as for shelter) straight over it. Move lifts the plot and its own pieces into a green preview (red only if you or a settler would be inside one of its pieces; yellow, a warning, where the ground under it is steeper than 30°); R turns it 90°. Remove plot keeps its pieces standing, unowned. Requirements are checked again whenever something is placed, removed, moved or resized. Plots, names, sizes, turns and owners are saved (older saves keep their plots, even ones smaller than the new minimum). Code: `building/plots/` and `ui/plot_panel.gd`.
- **Chimneys:** a chimney section (6 stone, 2 sticks, 1 rope) and a chimney top (6 stone) in the Furniture tab, unlocked by building a fireplace; Meshy models fitted to the fireplace chimney's 0.41 m square (a section 1 m tall, the top 0.4 m), their tops and bottoms flattened so they stack cleanly. A section snaps onto the fireplace's chimney or another section, the top onto either; Page Up/Down and turning work as for other pieces, and with snapping off they go anywhere. Chimneys pass through roofs like any piece may overlap another. While the fireplace burns, soft light grey smoke (lit from behind as well as in front, so it never goes dark) rises from the top of its stack (the top, or the highest section), widening and fading, drifting a little with a light breeze. The fireplace burns a layered particle fire (orange licks round a yellow core, a few sparks) on logs in its hearth (`building/fire_effects.gd`), and its light is a soft warm amber, faint by day and brighter at night, flickering. Furniture, the workbench, chest and campfire standing in a room, and a chimney through its roof, don't break the "closed room" check.
- **Furniture models:** the chopping block, tool rack, storage shelf, fireplace, workbench, bed (the Rustic Bed: a full 2 m long and, at its own proportions, 1.34 m wide, turned so its headboard is at the back against the wall) and foraging basket (0.62 m across its rope handle) show Meshy models, each fitted evenly into the piece's solid box (sized to the model's proportions, so collision, placement and backing onto walls match what you see; the fireplace's own flames and light burn in its hearth). The stone sorting table is still a placeholder shape. Build menu icons are rendered from the real pieces and models (see Build menu icons).
- **Build menu icons:** every build icon is staged the same way by `IconStudio` (`building/icons/`). It uses an orthographic three-quarter view from the front right, a little above, with a warm key, a soft cool fill and a subtle rim light from behind, rendered at 512 px and saved at 256 px with clean edges.
  - **Building pieces** stand solid among faint, pale, see-through outlines of the neighbours they attach to, placed by the snap rules. For example: an eave on the low edge of a faint roof; a gable on a faint wall under a faint roof; a ridge cap on two roof halves; corners between faint roofs; a valley eave corner under the faint L of roofs and eaves; a door in a faint doorway; stairs up to a faint raised floor; a pillar or pole under a faint floor corner; a beam on two faint posts; ladders and railings on faint floors; small, half, long and short walls beside a faint 2 m wall; curved walls on round floors; the cone roof on a curved wall; chimney pieces on a faint fireplace.
  - **Scale:** every piece in a tab is drawn at one scale (the tab's largest fills about 75%), so a 1 m wall really is half as wide as a 2 m one. Roof pieces turn so you look onto their tops.
  - **Furniture, workbench, chest, campfire and lean-to** have no ghosts. Each fills its own icon (at one scale, a basket would be a speck beside a bed) and stands on a small faint floor patch.
  - **In the slot**, the build slot draws the soft dark vignette behind the (transparent) icon, smooths it down with mipmaps and puts a small brass corner badge over it where size or angle tells pieces apart ("2×2", "1×1", "2 m", "1 m", "2.83 m", "26°", "45°", "22.5°"). A locked piece's dark silhouette keeps its shape.
  - **Re-rendering:** while working on the game (debug runs from the project, never in an export), the title screen quietly redraws any icon whose piece changed. Each icon's fingerprint in `assets/icons/build/icon_manifest.json` covers its buildable file and what that loads, its model folder, the piece-shaping and drawing code, and the studio. The console's `icons` (or `icons all`) does the same on demand. New pictures show at once; the editor picks up the files when it next gets focus.
  - **Template pictures** are the whole building from a front three-quarter view in low golden-hour sun (warm key, cool sky fill, rim from behind), tightly framed (`building/templates/template_thumbnail.gd`). Pictures older than that code are redrawn the same way.
  - **Inventory item icons** each fill their square and carry a soft drop shadow (coal, being dark, gets a soft pale glow). The three ores have their own rock colours (blue-grey tin with white flecks, tan copper with teal, dark iron with red), scrap is a warmer metal than stone, and the torch's head glows orange so it isn't mistaken for the spear.
- **Furniture (first version):** the Furniture tab holds simple placeholder furniture that counts toward plot requirements by name: bed (6 planks, 4 plant fiber), foraging basket (4 plant fiber, 2 sticks), chopping block (2 wood), tool rack (3 planks, 2 sticks), stone sorting table (4 planks, 2 stone), storage shelf (4 planks) and fireplace (6 stone), plus the campfire, workbench and storage chest. The new pieces unlock with the first planks, demolish for a full refund and save. Furniture (and the workbench, chest and campfire) stands on whatever floor, foundation or ground is under the crosshair; with snapping on it sits on a 0.5 m grid in the floor's own frame in 90° turns, and the bed, shelf, tool rack and workbench back up flush against a wall they're close to. Like pieces, it may overlap anything. The fireplace burns without fuel and warms like a campfire (6 m), so inside a closed house it keeps you warm.

**Templates**

- **Build it yourself or use a template.** A placed template becomes ordinary pieces the player can change.
- **Placing:** the template shows fully built with real textures, plus a green outline glow (red only if someone would be inside it, yellow for steep ground).
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
    - It glows green; red only where you or a settler would be inside one of its pieces; yellow (a warning, still placeable) where the ground under its foundations is steeper than 30° or it would stand in water. Pieces that exactly repeat ones already there are left out.
    - R turns it 90° and Alt + wheel 15°; Page Up / Page Down raise and lower it (Alt: finely); Backspace resets the turn and height.
    - Near another building it snaps where one of its outer snap points meets one of theirs, by the usual snap rules at its current turn.
    - Left-click creates the plot (the template's type and size, adjustable afterwards in plot view) with everything in it as a ghost. Placing costs nothing.
  - **Ghosts:** each ghost shows its full detailed look (every plank, shake and rafter; furniture and the workbench, chest and campfire their models) in a soft see-through neutral grey (#9a9a9a, about 30% opaque), slightly lighter and stronger toward the edges where a surface turns away from you. The ghost under the crosshair (the one you'd fill) brightens a little. Code: `building/templates/ghost_look.gdshader` and `BuildPiece.set_ghost`.
    - **Rules:** ghosts aren't solid (the player, settlers and every physics check pass through them), and don't count as built for requirements, shelter, settlers, joint details or fires.
    - **Aiming:** aim at a ghost with the hammer and it brightens, and the placement panel shows its name and cost (red if you're short).
    - **Building:** left-click builds it from your inventory only, turning it into the real piece, workbench, chest or campfire (not while you're standing in its way).
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
  - **Size:** each storage shelf in a working Storehouse adds 8 slots (a slot holds any amount of one item, as in a chest). All working Storehouses together form one shared pool, the town storage.
  - **Tracker:** a Storehouse's tracker shows "Town storage: 14/24 slots" for the whole pool, or "closed until it's working".
  - **Opening it:** E on any storage shelf in a working Storehouse ("Open town storage") opens the Town Storage screen beside your inventory, in the chest screen's style:
    - the whole pool, sorted by category (food, materials, tools, other), with the slots in use in the title and each category's total;
    - drag or shift-click to move stacks across;
    - Deposit resources moves every material and food item from your inventory into it, leaving tools and the action bar alone.
    - It scrolls past three rows. A shelf in a Storehouse that isn't working says so.
  - **Settlers:** job output at dawn goes into town storage while it has room, otherwise into the hut's own chest. What fits in neither is lost: "Forager's Hut: Town storage full (3 herbs lost)". Settlers eat from town storage first, then from plot chests as before, and a House's "Food stored" counts it.
  - **Refunds:** shrinking a plot refunds its removed pieces into town storage first, then your inventory, then a bundle at your feet. Demolishing by hand still refunds to your inventory. Building (placing pieces, filling ghosts) still takes only what you carry.
  - **Saved:** with the Storehouse plots, each holding a share of the pool.
  - **Shrinking:** when a Storehouse stops working, loses a shelf or is removed, the pool keeps what still fits. The rest drops in a bundle by that Storehouse, with a message, so nothing is lost.
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
  - **Options:** master, music and effects volume (the Music and Effects buses are made if missing); window mode (windowed, fullscreen, borderless); resolution (windowed only); V-Sync; mouse sensitivity; invert Y; field of view (sprinting still widens it).
  - **Saving:** changes apply at once and are saved to `user://settings.cfg`.
- Developer console (debug builds only, never in a release build; `dev/`):
  - **Opening:** ~ opens and closes a brass plaque across the top of the screen, with a monospace scrolling log, an input line, history on Up/Down, and Tab completing command and item names. While it's open the player stands still and other keys are ignored.
  - **Commands:** help, give <item> [amount], give_all [amount], freebuild, unlock_all, god, fly, time <0–24>, day, spawn_settler [count], tp <x> <z> / tp settlement, clear_inventory, save, load. Unknown commands and bad arguments print the right usage.
  - **Toggles:** freebuild (pieces, furniture, buildings, ghosts and crafting cost nothing and refund nothing), god (hunger and stamina never drop) and fly (Space up, Ctrl down, Shift faster, through everything). They aren't saved and start off every time a world opens. A "DEV" tag in the top-right corner names the ones that are on.
  - **Shortcuts:** F9 runs spawn_settler and F10 runs day.
- Compact steampunk-brass HUD, laid out at 1920 × 1080 and scaling with the window (same look at 1080p and 4K): the brass vitals panel bottom left (`assets/ui/vitals_panel.png`: a half-gauge whose needle shows stamina, red zone at full, over hunger and stamina channels that fill gold and blue-green with soft ends, labelled "Hunger" with a steak and "Stamina" with a lightning bolt), the brass compass with its small clock mounted on the action bar's left end (the bar's own left scrollwork is trimmed off), drawn on top, its brass right up to slot 1's frame and its loose side curls tucked under it (`compass_clock.png`: a needle pointing north relative to where you face, hour and minute hands showing the in-game time), a thin brass ring crosshair, what E would do with the thing you aim at in a line under the crosshair, and a centred row of the controls that apply right now just above the action bar (label and key badge pairs; "Eat Berries [F]" while carrying berries, "Demolish [MMB / Hold X]", "Snap [Z]" and "Plot view [P]" with the hammer out), with a small panel above it while building or demolishing (piece icon, name, cost or refund, one line of details). The action bar is the brass bar art (`action_bar.png`) with a slot picture over each opening: a plain slot when it holds something, a gear slot when empty, and a gold, glowing slot for the selected one. Menus are drawn 1.5× (`MenuStyle.MENU_SCALE`). The blank brass plaque (`plaque.png`, 9-sliced just inside its corner rivets, edges stretched) frames the build placement panel, build menu, inventory, crafting and pause menus; the title screen alone uses the ornate `panel_frame.png`. Buttons, slots and key badges keep a restrained code-drawn brass style (`ui/brass_style.gd`: thin bevelled worn-gold borders, recessed slots, a faint gear in empty inventory slots). Anything missing from `assets/ui/` is drawn in code

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
