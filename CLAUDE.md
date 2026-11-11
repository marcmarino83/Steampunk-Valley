## Working on Steampunk Valley

- Read DESIGN.md before making changes.
- Testing: don't launch the game window or run scripted play-throughs unless I ask. After changes, run one quick headless check (godot --headless --quit) to catch script errors, fix any that show up, and stop there. I'll play-test by hand.
- If something can only be confirmed by playing, list what I should check instead.
- After any change to building, snapping or placement code, run tests/snap_regression.gd (headless: `godot --headless --path . res://tests/snap_regression.tscn --quit-after 40000`, under a hard time limit of 180 seconds) and fix any failure before reporting.
- Don't commit; I'll commit myself after testing.
- Edit files only with the editor tools, never with shell commands (sed, echo, PowerShell redirects). If a file gets corrupted, stop and tell me instead of repairing it line by line.

## Building pieces

- Every building piece has fixed dimensions. Never build pieces that stretch, resize or regenerate to fit where they're placed. When a new size is needed, add a new fixed piece. (Raising or lowering a free piece with PgUp/PgDn is fine: that moves it, it doesn't reshape it.)
- Every piece follows the building grid standard (details in DESIGN.md, Building system):
  - Horizontal unit 1 m, in 2 m cells: widths and lengths of 1, 2 or 4 m, on the 1 m grid.
  - Vertical unit 1.25 m: heights are whole units (the 0.625 m Wall Strip is the one half unit), with bottoms and tops on unit heights. Foundations' tops are 1.25 m above the ground.
  - Walls are 0.2 m thick, centred on their line. Floors are 0.2 m thick, top on the level. Foundations fill their cell and go 2 m into the ground. Beams are 0.2 m square with their top on the level.
  - Posts are 1.25, 2.5 or 5 m. Beams are 1, 2 or 4 m (plus the diagonals).
  - Exempt:
    - roof pitches, 26.6° and 45° (only their bottoms on unit heights);
    - the octagon and circle families;
    - the 0.5 m roof overhang trim;
    - window and door frames sticking out as trim;
    - railings (1.0 m tall).
  - Collision stays within 2 cm of the drawn look, and common joins meet at 0 mm. The snap regression checks both.
  - When a piece is resized, old saves and templates must still load: add the change to building/grid_upgrade.gd (bumping GRID_VERSION) so placed pieces keep their snap position.

## Running the game for checks or screenshots:

- Every scripted run must end itself: the capture script calls get_tree().quit() once it has taken its screenshots, and also passes --quit-after <frames> on the command line as a backup (for example --quit-after 3000).
- Always wrap the run in a hard time limit (about 120 seconds) that kills the Godot process if it’s still running, so a hang can never block you. On Windows, start it with a timeout and stop the process afterwards if needed.
- Never leave a Godot game window open after a check. If a run had to be killed, say so in the report.
- Default to the headless check only (project loads, world scene opens, no script errors). Don’t launch the game for screenshots or scripted play-throughs unless the task asks for it, or the change is visual (UI, art, materials, lighting, layout).
- When a visual check is needed, do it in one run: set up everything needed, capture all screenshots, then quit. Don’t re-run to try small variations; if a fix is needed after looking, make it and do at most one more run.
- Never run scripted tests just to confirm logic I can test by hand. List the checks for me instead.
If you think a run is worth it for a non-visual change, ask first in one line.


## New assets

- I drop new Meshy models straight into assets/. When you find new model files there, move each into a sensible folder (tools, pickups, buildables, etc.), rename it in lowercase with underscores (e.g. lean_to.glb), and keep its textures with it.
- Tell me each model's triangle count and file size. Flag anything that looks too heavy for what it is, but don't change the model.
- Cap textures on import: 1024 for most things, 512 for small pickups.
- Delete unused extra files the import creates (numbered texture copies). To stop them coming back, set the model's import to not extract its built-in textures (embedded image handling: discard) and give it a material that uses the named textures.
- Keep pickup and buildable models out of the Object Painter's palette.
- .gitignore keeps out any hd/ folder and .zip files, but git can't ignore files by size. Whenever you add, move or change files, check for any file over 50 MB that git would commit (anything outside the ignored paid tree packs and hd/ folders) and warn me about it, with its size, before I commit. GitHub refuses files over 100 MB.
- When a model is replaced by a lighter version, don't leave the old one behind unused: ask before deleting it, or put it in an hd/ folder so it stays out of git.

## File organization

- Never put new scripts or scenes in the project root. Only project.godot,
  icon.svg, DESIGN.md, CREDITS.md, CLAUDE.md and git/editor config live there.
- Keep each script with its scene in a feature folder: player/, ui/,
  building/, world/, crafting/, tools/, iron_tier/. If nothing fits,
  make a sensible new folder and tell me.
- Models and textures go in assets/; code and data go in the feature folders.
- Use lowercase_with_underscores for all file and folder names.
- When moving files, update every reference and use git mv.
