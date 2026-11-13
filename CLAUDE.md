## Working on Steampunk Valley

- Read DESIGN.md before making changes.
- Testing: don't launch the game window or run scripted play-throughs unless I ask. After changes, run one quick headless check (godot --headless --quit) to catch script errors, fix any that show up, and stop there. I'll play-test by hand.
- If something can only be confirmed by playing, list what I should check instead.
- Building tests come in two suites, both run by `tests/run_suite.ps1` (headless, each chunk under its own hard 180-second limit, so nothing is skipped):
  - Quick suite (`powershell -File tests/run_suite.ps1 quick`, under a minute): after every change to building, snapping or placement code. Fix any failure before reporting.
  - Full suite (`powershell -File tests/run_suite.ps1 full`: every regression case, remove-and-replace on every template, the aim check on every template): only when I ask, or before a commit.
  - Report which suite ran, its time, and whether anything failed or was skipped (the last line says). Don't raise the time limits: if a chunk gets near its limit, split it.
- Don't commit; I'll commit myself after testing.
- Edit files only with the editor tools, never with shell commands (sed, echo, PowerShell redirects). If a file gets corrupted, stop and tell me instead of repairing it line by line.
- Never use orange for highlights, indicators, warnings or status colours (previews, outlines, glows, selection, alerts). Exceptions: brass and gold interface materials, fire and light, sunlight, and object icons and markers.
- New panels must be built on the standard panel builder (ui/brass_panel.gd: header, sections, action row, key-hint row) and use only BrassStyle's palette, type sizes, spacing and button kinds (DESIGN.md, Interface style). Never hard-code an interface colour, and never write instruction paragraphs into a panel: key hints go in the hint row, longer explanations in tooltips. Follow the trimming rules in DESIGN.md's Interface style (nothing twice, no hints for buttons, collapsed checklists, details on demand). E only closes panels and interacts; tabs switch with Q and R.

## Building pieces

- Snapping rules are kept to the absolute minimum. A "rule" is any code that rejects, skips, prefers or limits a snap position or rotation. Fix problems with typed pairings (data) wherever possible, never with piece-specific special cases. Before adding a rule: explain why no pairing can solve it, which existing rules it could interact with, and get my OK first. Prefer removing or simplifying a rule over adding one. Keep a numbered list of every active snapping rule in DESIGN.md.

- Every building piece has fixed dimensions. Never build pieces that stretch, resize or regenerate to fit where they're placed. When a new size is needed, add a new fixed piece. (Raising or lowering a free piece with PgUp/PgDn is fine: that moves it, it doesn't reshape it.) The one exception is paths (Dirt, Gravel, Stone, Remove): they're laid by dragging out a strip, fixed 2 m width, free angle, length in 0.5 m steps. Nothing else may be sized by dragging.
- Every piece follows the building grid standard (details in DESIGN.md, Building system):
  - The grid is 2 m, set by the foundation (2 m) and the 45° triangle wall (2 m base, 2 m tall).
  - Horizontal: 2 m cells with a 1 m half step; widths and lengths of 1, 2 or 4 m, on the 1 m grid.
  - Pieces that match a wall's height come in two permanent families, both in the build menu:
    - Standard: built on the 2 m wall, with a 1 m vertical unit (half wall 1 m, wall 2 m, strip 0.5 m). Heights are whole units (or the half-unit strip), bottoms and tops on unit heights.
    - Tall: built on the 2.5 m wall, with a 1.25 m unit (half wall 1.25 m, strip 0.625 m). Tall pieces are named "Tall …".
    - New wall-height pieces must come in both families unless I say otherwise.
    - Nothing else may be sized from the Tall family unless I specifically ask.
  - Pieces with no wall height to match are on the standard sizes only: poles 1, 2 or 4 m; the fence 1 m; foundations, their tops 1 m above the ground; beams; the fireplace and chimney.
  - Walls are 0.2 m thick, centred on their line. Floors are 0.2 m thick, top on the level. Foundations fill their cell and go 2 m into the ground. Beams are 0.2 m square with their top on the level.
  - Straight beams are 2 or 4 m only. Each diagonal beam is exactly as long as the sloped edge of its matching triangle on a 2 m base (26.6° and 45°), its ends on the triangle's corners, plus double-length ones for 4 m spans.
  - Exempt:
    - roof pitches, 26.6° and 45° (only their bottoms on unit heights);
    - the octagon and circle families;
    - the 0.5 m roof overhang trim;
    - window and door frames sticking out as trim.
  - Collision stays within 2 cm of the drawn look, and common joins meet at 0 mm. The snap regression checks both.
  - When a piece changes, old saves and templates must still load as they were: add the change to building/grid_upgrade.gd (bumping GRID_VERSION). Where a piece of the old size still exists, load as that piece unchanged; otherwise keep its snap position.

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
- Scripts have a soft limit of 450 lines (tests 800). New features go in their own scripts (a child node or a helper), not into an existing large one. When a change would take a script past the limit, or it's already past it, say so in the report and propose the split instead of adding to it; don't split without an OK. Splits are behaviour-identical, one script per commit, checked with the tests listed for it in DESIGN.md's Code structure.
- Keep each script with its scene in a feature folder: player/, ui/,
  building/, world/, crafting/, tools/, iron_tier/. If nothing fits,
  make a sensible new folder and tell me.
- Models and textures go in assets/; code and data go in the feature folders.
- Use lowercase_with_underscores for all file and folder names.
- When moving files, update every reference and use git mv.

## Code style

- Follow Godot's GDScript style guide. Lines under 100 characters (code and comments), wrapping long comments onto several lines. Comments explain why, not what. Don't reformat whole files on their own; when you change a script, wrap the over-long lines in the parts you touch.
