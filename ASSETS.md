# Third-party assets

Only CC0 / permissive assets. Never use assets, names, UI or audio from Gridiron.

| Asset | Path | Source | License | Used for |
|---|---|---|---|---|
| Universal Animation Library 1 + 2 (rigged mannequin + 86 animations, one 65-bone skeleton) | `assets/characters/UAL{1,2}_Standard.glb` | Quaternius (quaternius.itch.io/universal-animation-library, -2) | CC0 1.0 (`assets/characters/LICENSE_Quaternius_UAL.txt`) | Athlete bodies + animations (uniform colors are baked per bone region at runtime) |
| American football player, ready (helmet, facemask and chin strap) | `assets/characters/InnersceneHelmet.glb` | [Innerscene, adapted from MakeHuman](https://www.innerscene.com/tools/library/3d-parts/american-football-player-ready-3d-person-team-sports-aad6f516) | CC0 1.0 | Local team's helmet, resized and fitted with a customizable crown stripe |
| Moon 01 (regolith) | `assets/textures/regolith/` | Poly Haven (polyhaven.com/a/moon_01) | CC0 | Ground outside the stadium |
| Concrete034 | `assets/textures/concrete/` | ambientCG | CC0 | Stadium concrete |
| Metal009 | `assets/textures/metal/` | ambientCG | CC0 | Light towers / trusses |
| Grass004 | `assets/textures/grass/` | ambientCG | CC0 | Turf detail |
| Space skybox (galaxy) | `assets/sky/` | Kenney (Skyboxes Space) | CC0 (`assets/sky/LICENSE_Kenney.txt`) | Night sky panorama |
| Graduate | `assets/fonts/Graduate-Regular.ttf` | Google Fonts (github.com/google/fonts) | SIL OFL 1.1 (`assets/fonts/graduate_OFL.txt`) | Display type: wordmark, PLAY, names, jersey/yard numbers |
| Teko (variable) | `assets/fonts/Teko-UI.ttf` (built from `tools/brand/font_src/Teko-VF.ttf`) | Google Fonts (github.com/google/fonts) | SIL OFL 1.1 (`assets/fonts/teko_OFL.txt`) | UI/HUD type: nav, buttons, headings, scorebug. Rescaled by `tools/brand/scale_fonts.py` |
| Barlow Semi Condensed Medium + SemiBold | `assets/fonts/BarlowSemiCondensed-*-UI.ttf` (built from `tools/brand/font_src/`) | Google Fonts (github.com/google/fonts) | SIL OFL 1.1 (`assets/fonts/barlow_OFL.txt`) | Body type: paragraphs, descriptions, help. Rescaled by `tools/brand/scale_fonts.py` |
| Team logos (8 emblems: helios, nebula, eclipse, regolith, selene, apogee, quasar, tycho) | `assets/teams/<id>.png` (512 px) | Generated for this project on 2026-11-26 with OpenAI Codex CLI 0.172 built-in image generation (prompt: `tools/brand/team_logos_prompt.md`). The white background was keyed out and the images were cropped and resized by `tools/brand/team_logos.gd` | Original to Crater Bowl. Machine-generated, not derived from any third-party logo; under OpenAI's terms the output belongs to the project. Checked by eye for text and real-team likeness | Team logos on the scorebug and hold-Tab board (#233) |

Original (made in this repo): stadium bowl/crowd/towers/arches/jumbotron geometry, turf/sky/ribbon/emblem shaders, helmet + facemask + pads, football, overlay.

The opponent uniform is an original skinned model with its own padded jersey,
gloves, pants, cleats, helmet and cage. Open `tools/characters/OpponentUniform.blend`
in Blender to edit the authored asset. Export a Y-up GLB with skinning enabled
and animations disabled to `assets/characters/OpponentUniform.glb`. Keep the
existing bone and material names for in-game animation and cosmetics.
`tools/characters/build_uniforms.py` rebuilds both GLBs from the original
geometry recipe and the Innerscene download. The local team uses the rigged
Quaternius body with the imported helmet and cage.
