# Team logo prompt (#233)

Run from a scratch directory outside the repo: `codex exec --skip-git-repo-check -s workspace-write "$(cat tools/brand/team_logos_prompt.md)"`, then process the raw PNGs with `tools/brand/team_logos.gd`. Prompt as used (2026-11-26, codex-cli 0.172, built-in `image_generation`). Codex produced 13 drafts and kept the eight below. SELENE's first crescent-and-star read like a flag or religious symbol, so it was regenerated alone with the helios logo attached as a style reference and this concept: "a bold silver crescent moon with a sweeping orbit arc crossing in front of it and a few small round craters on the crescent. Do NOT include any star".

---

You are making team logo art for an original arcade football video game set in a stadium inside a moon crater. Use your built-in image generation tool to create EIGHT separate images, one per team below. Do not write code to draw them; use image generation.

Shared style for all eight (they must look like one league's set):
- Flat vector-style sports emblem, bold and simple, readable at 32 px.
- Circular badge silhouette, centered, filling about 85% of the square canvas.
- A thick dark navy (#0B0F1E) outline around the entire outer silhouette.
- Flat colors with at most one subtle highlight shade, no gradients, no photo texture, no 3D bevel.
- Plain flat solid pure white background (#FFFFFF) outside the badge. No shadow, no checkerboard.
- Absolutely no text, letters, numbers, wordmarks or initials anywhere.
- Original design. Must not resemble any real sports team logo (NFL, NBA, MLB, NHL, MLS, college) or any brand.
- Square, 1024x1024.

Teams (id: concept; primary color / secondary color):
1. helios: a radiant stylized sun with sharp rays rising over a moon crater rim; gold #F2BF26 / deep navy #1A2147
2. nebula: a swirling cosmic gas-cloud spiral with a few small stars; cyan #4DCCF2 / violet #6B3DB3
3. eclipse: a dark moon disc covering the sun, with a jagged crimson corona ring; crimson #DB293D / near-black #141419
4. regolith: a rugged cracked lunar boulder with small craters; rust orange #E66B29 / slate gray #4D525C
5. selene: a crescent moon cradling a four-point star; silver #CCD6E6 / royal blue #294DBF
6. apogee: a small rocket climbing along a curved orbit trail; lime green #8CE040 / dark teal #0D474D
7. quasar: a blazing star core with two opposing energy jets and an orbit ring; magenta #EB40BF / midnight indigo #1F1A4D
8. tycho: an impact crater with bright ray streaks bursting outward; purple #804DD9 / mint #8CF2CC

Save each final image as PNG to <scratch dir>/<id>.png (for example <scratch dir>/helios.png). When done, list the eight saved paths.
