# Scene-aware save checkpoint

2026-10-06. This checkpoint extends the authoritative story state with two allowed world locations: FOG_HARBOR and PILOT_CABIN. It remains the same single StateStore writer; presentation cannot modify scene or anchor data directly.

- Schema 3 preserves schema 1 and 2 saves through explicit migration
- A free travel command is available without story, outfit, inventory or relationship gates; an active conversation must first be suspended
- Travel commits the destination scene and its local recovery anchor together and invalidates old interaction callbacks
- Resuming a story scene selects its corresponding location without skipping expression choices
- Saving and reloading indoors preserves the scene, local anchor, outfit and suspended story
- Invalid cabin coordinates and unknown scene IDs reject the entire transaction

Local automated checks: content 24, domain 2041, save recovery 80, plus JSON and source-boundary checks. These results do not verify the new cabin's actual geometry, camera, door traversal, GUI playthrough or exported package. Those are tracked in AI_BOARD and remain open.
