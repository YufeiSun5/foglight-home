# Snapshot-driven game UI

## Composition

`src/presentation/ui/game_ui.gd` is an additive full-rect Control. A composition root adds it beneath a CanvasLayer, calls `bind_flow(flow)`, and connects `intent_requested` to the public `flow.submit`. The UI reads only `view()` and `intent()` and never imports StateStore, save adapters, or domain writers. Connect the world's `interaction_hint_changed(String)` to `ui.set_world_hint(String)`.

Public inspection helpers return isolated snapshots/commands: `rendered_snapshot()`, `preview_appearance()`, `command_for(key)`, `button_for(key)`, and `surface_rects()`. `unbind_flow()` disconnects refresh and invalidates retained local callbacks. These helpers do not submit actions.

Controls: I opens the wardrobe; J opens the journal outside combat; Escape opens/closes menus; Space continues non-choice dialogue; 1–3 selects exact displayed choices; F5 saves and F9 loads through the facade. Transition panels allow only cancellation with the exact transition ID. The composition root must not retain a separate Escape-to-quit handler during gameplay.

Wardrobe selection is local preview. Both preview images consume one draft appearance. Apply emits one `outfit` intent. Cancel/close/load discard uncommitted preview; the world and dialogue portrait always consume committed `view().appearance`. Color indices are explicitly blue 0, indigo 1, green 2, cream 3, matching the existing wardrobe manifest. All 16 combinations remain available from the first scene.

The journal contains exact committed lines from the facade, paginated in 30-entry pages. No future story, tasks, relationship points, unlock requirements or invented NPC portraits are introduced. Existing NPC idle art is explicitly labeled as a temporary pixel depiction. Existing protagonist art uses the provided three-expression atlas; wary/hurt share the concerned frame.

## Reproducible checks

Run `bash tests/ui/verify-ui.sh` with Godot 4.6.3 and Python FontTools 4.61.1 available. The published font is already built; FontTools is only a verification/build dependency, not a game dependency. The runner performs a bounded headless asset import, so a clean checkout needs no existing editor cache. It creates isolated temporary home/cache/config/data directories and never reads or writes player save slots. The integration suite uses real GameFlow and an in-memory SavePort. The layout fixture renders each approved node at 1280×720 and 960×540 and checks surface/button bounds and unclipped text lines. It also bounds a 20,000-entry journal to one page of controls.

`tests/ui/demo_ui.tscn` is a separate UI review harness. It is not the default game entry, a 3D scene, or a disk-save test. Launch it explicitly with `godot --path . res://tests/ui/demo_ui.tscn`. Optional user arguments after `--`: `--choices`, `--wardrobe`, `--journal`, `--pause`. Coordinate access to the shared cloud desktop and run only one GUI session at a time.

## Font source and license

`assets/fonts/FoglightUI-SC.otf` is a renamed offline subset of the installed Debian `fonts-noto-cjk` Simplified Chinese face. Original embedded Adobe copyright, complete SIL OFL 1.1 and exact source/output SHA-256 provenance are retained in `assets/fonts`. `python3 tests/ui/build_ui_font.py` rebuilds it from that installed source after content/UI/status text changes; reimport the font and run the coverage check afterward. This license applies to the font only, not the project. No font is downloaded by the build or game.

Headless checks do not establish rendered appearance, GUI input quality, GPU performance, Windows compatibility or final portrait art quality. Current acceptance and visual-test results belong in the project work board.
