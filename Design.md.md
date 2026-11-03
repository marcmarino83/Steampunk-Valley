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
| 1. Scrap and Survival | Hand tools, campfire, rough shelter | Scrap, wood, stone, berries, coal | Cold, hunger, wolves |
| 2. The Forge | Forge, workshop, first boiler, better tools | Iron and copper ore | Lone Hollow scouts drawn by forge smoke |
| 3. Steam Power | Sawmill, water wheel, steam pump, steam shovel, walls and steam defenses, clockwork helpers | Gears, springs, copper plating from Hollows | Hollow raiding parties |
| 4. The Sky | Restored airship dock, trade with passing airships, own airship, clockwork guardians | Construct cores, trade goods | A major Hollow assault drawn by the dock's engines |

**How technology unlocks.** Two routes, mixed:

- **By doing:** chopping, mining, and crafting teach the basics (Medieval Dynasty style).
- **By discovering:** schematics found in ruins, and Hollow parts studied at the workshop, unlock the advanced tech.

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

**Aether.** The golden energy that gave the Gilded Empire its name. It powered the great control engine and every construct core, and whatever went wrong with it is what turned the constructs into Hollows. The player harvests aether from defeated Hollow cores, so magitek, the story, and the enemies all share one source.

## Settlement and defense

The player starts out doing everything alone and gradually becomes the leader of a working settlement that has to defend itself.

- **Settlers:** other refugees arrive once there is housing, food, and warmth.
- **Jobs:** settlers are assigned work such as woodcutter, miner, stoker, or farmer, and the settlement produces on its own.
- **Defense:** walls, watchtowers, and steam-powered defenses against Hollow raids.
- **Clockwork guardians:** late game, reprogrammed construct cores become defenders, turning the Empire's weapons against its ruins.
- **Terraforming:** a craftable, coal-fuelled steam shovel raises, lowers, and flattens ground for foundations, ponds, and channels from the river. Height-based only, so no caves or tunnels. It needs a save system so changes persist.

## World and look

The valley is built from real-world elevation data and is heading toward a realistic natural look, with steampunk ruins layered on top.

- **Terrain:** a heightmap of rolling hills in the English Midlands (36 to 226 m real elevation), built in chunks. Currently 1500 m across with the hills exaggerated. The rest of the heightmap is room to expand, and airship travel can open new regions later.
- **Water:** a single water level fills the low ground, forming the river and lake.
- **Visual target:** a realistic forest-and-stream look like the reference screenshot (rocky slopes, ferns, deer). Lighting, fog, shaders, and procedural grass come first; real art assets (Poly Haven, ambientCG, asset packs) replace placeholders in a later beauty pass.
- **Places to discover:** the ruined airship dock, an abandoned workshop, and rusting machinery in the hills.

## Regions

The world grows one region at a time: each region is its own open map, and airships carry the player between them. Names beyond the Valley are placeholders.

| Region | Character | Key resources | Hollow threat |
| --- | --- | --- | --- |
| The Valley (start) | Rolling hills, river and lake, crash site, outpost ruins | Wood, scrap, coal, stone, iron, copper | Scouts and small raids |
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

**Known issues**

- Eat and campfire prompts show even when the player has no berries or wood
- Some rocks float or sit sideways on steep slopes
- Hills look domed and rocky; try a lower height scale for true rolling hills
- The near map edge ends in a cut-off wall

## Roadmap and open questions

Next comes filling the valley with things to find, then crafting and building, then the Hollows.

**Next up, in order**

1. More gatherables placed by the terrain script: stone, iron and copper ore, mushrooms, herbs
2. Places to discover: the ruined airship dock and an abandoned workshop
3. Wolves
4. Crafting and first buildings, with a flatten-ground tool
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
