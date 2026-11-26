# Session Tracker

A [Dungeon Rampage Haxe](https://github.com/Tutez64/Dungeon-Rampage-Haxe) mod that adds up what the day and the current launch of the game earned — gold, XP, chests, runs, floors and time — and keeps the day's total across runs in a file of its own. It runs alongside [Dungeon Minimap](https://github.com/Drandoxy/DRH-Mod-Dungeon-Minimap) and does not depend on it.

<!-- drh:show -->
A small panel in the bottom-left corner of the screen shows the totals: gold and XP earned inside dungeons, chests opened, runs, floors, time played and the average gold and XP of a run, plus the run in progress or the last one and the items it added to your inventory, with legendaries in orange.

- **Ctrl + Shift + T** shows or hides the panel, the way the Dungeon Minimap uses Ctrl + Shift + M. **F3** clears the totals of the tab on screen. F6, F7 and F9 are left to the mods that use them.
- Drag the panel by its header to move it.
- Two tabs, switched by clicking them: **SESSION** (the one the panel opens on) is this launch, from zero every time the game opens and never written to the file; **TODAY** is the calendar day, kept in `session.json` in the mod's data folder, rolled at midnight with the earlier days as history. Both add up the same runs, so the session is the part of the day that this launch earned.
- **CHART**, at the right of the tab row, opens a line chart of the days in the file. Click the metric's name to cycle GOLD, XP and CHESTS, and 7D, 30D or ALL for the range; the highest day of the range reaches the top, and a day without an entry leaves a gap in the line.

Gold counts only what was earned inside the dungeon: the balance is sampled when the first floor loads, so shopping in town is never added to it. XP is the end-of-dungeon report's total, or the XP orbs picked up when the game sends no report. Chests are the treasure the party collected, and every chest counts for the whole party.

Item names come from your inventory when you are back in town, compared with it when the dungeon started. Weapons are compared by kind, power, level and rarity, because the API has no per-weapon id yet: two identical weapons still show as a count of two. Items sold or opened outside the run are not subtracted. The panel starts in the bottom-left corner so it does not cover the Dungeon Minimap panel, which defaults to the top-right; drag it for another spot, the position is not remembered between starts.

Both keys are set in Settings → Controls, where they can be rebound if another mod or the game wants them. A key binds once, compared by the key alone, so T belongs to this mod until it is rebound. Tested with DRH 18 and Mod API 1.5.0.

Gold and XP capture reads the game's own objects through `context.core`, so a DRH update can break those counters; the panel and the rest keep working without them.
<!-- /drh:show -->

## Capture technique

The gold and XP capture follows the approach of [Dungeon Minimap by Drandox](https://github.com/Drandoxy/DRH-Mod-Dungeon-Minimap), itself based on [Xk's Minimap](https://github.com/Xkaka505/DRH-Mod-Minimap) (both GPL-3.0):

- Gold is the delta of the account balance the server pushes to the live player object (`PlayerGameObjectOwner.basicCurrency`), sampled when the run starts and again at the end screen.
- XP is read from the end-of-dungeon report (`DistributedDungeonSummary.report`), and from the dungeon area's collected XP doobers (`Area.expCollected`) as a live counter and a fallback.
- Chests are the treasure doobers in the dungeon area's `treasureCollected` list.
- The end of a run is the end screen (`DistributedDungeonSummary`) or the return to town, so a run is never counted twice.

No code was copied from either minimap. Their capture was reimplemented against the current game sources, and this mod's own files were written for it; the license below is the template's GPLv3 regardless.

Requires DRH 18 and Mod API 1.5.0 or a compatible later 1.x version. [GPLv3](LICENSE).
