## Working on Steampunk Valley

- Read DESIGN.md before making changes.
- Testing: don't launch the game window or run scripted play-throughs unless I ask. After changes, run one quick headless check (godot --headless --quit) to catch script errors, fix any that show up, and stop there. I'll play-test by hand.
- If something can only be confirmed by playing, list what I should check instead.
- Don't commit; I'll commit myself after testing.

## New assets

- I drop new Meshy models straight into assets/. When you find new model files there, move each into a sensible folder (tools, pickups, buildables, etc.), rename it in lowercase with underscores (e.g. lean_to.glb), and keep its textures with it.
- Tell me each model's triangle count and file size. Flag anything that looks too heavy for what it is, but don't change the model.
- Cap textures on import: 1024 for most things, 512 for small pickups.
- Delete unused extra files the import creates (numbered texture copies).
- Keep pickup and buildable models out of the Object Painter's palette.

## File organization

- Never put new scripts or scenes in the project root. Only project.godot,
  icon.svg, DESIGN.md, CREDITS.md, CLAUDE.md and git/editor config live there.
- Keep each script with its scene in a feature folder: player/, ui/,
  building/, world/, crafting/, tools/, iron_tier/. If nothing fits,
  make a sensible new folder and tell me.
- Models and textures go in assets/; code and data go in the feature folders.
- Use lowercase_with_underscores for all file and folder names.
- When moving files, update every reference and use git mv.
