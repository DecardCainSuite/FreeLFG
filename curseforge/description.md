# Free LFG — CurseForge

## Fields

- **Project name:** Free LFG
- **Summary:** The group finder as a compact, sortable table: leader, roles, free slots, one-click whisper from a template, and live filters you write yourself.
- **Main category:** Chat & Communication
- **Extra categories:** Miscellaneous
- **Logo:** `images/FreeLFG-logo-1024.png` (the 400 px version is there if needed)

## Gallery (title — description)

1. `images/flfg_1.png` — **Free LFG** — The group finder, as a table you can read.
2. `images/flfg_2.png` — **Every group on one screen** — Sort any column; roles, free slots, state and age at a glance; whisper the leader in one click.
3. `images/flfg_3.png` — **Filters you write yourself** — (heal >= 1 or tank >= 1) and dps <= 2: the table updates as you type.
4. `images/flfg_4.png` — **Only the dungeons for your level** — Activities at your level or all of them, tick several.
5. `images/flfg_5.png` — **Right on the game's window** — A Free LFG tab next to the game's own, with the same frame.
6. `images/flfg_6.png` — **Make it yours** — Columns, font, scale, message template and per-character profiles.

---

## Description (paste into the Markdown editor)

# Free LFG

A readable Looking For Group window for WoW Forever: one compact table instead of a long list to scroll.

## The table

- One line per group: **leader** (class colour, level when the game gives it), **activity**, **size** (n/5, n/40), **roles** (tank / healer / DPS counts with icons, plus free slots), **state** (Relaxed, Competitive, Full, Delisted...), **time listed**, and the **title / comment**.
- Click a column header to sort, click again to reverse. Ties keep the game's own order.
- Pick a category and one or more activities (or "activities at my level"), then press **Refresh**. Free LFG also follows the searches done in the game's own window.
- Row height, font, font size, scale and visible columns are yours to set. Mouse wheel scrolling with a slim scroll bar. Hover a group for the full details and its members.

## Filter live, as you type

A box above the table filters the rows **instantly**. It only changes what the table shows, never the game's search.

- Variables: `tank`, `heal`, `dps` (in the group), `tankfree`, `healfree`, `dpsfree` (open slots per role), `members`, `free`, `level`, `age` (minutes), `solo` and `delisted` (1 or 0).
- Comparisons: `>= <= > < = !=`, ranges `dps in 1..2`, `1 <= dps <= 2`, `dps between 1 and 2`.
- Combine with `and` / `or` / `not` (or `&&` `||` `!`) and parentheses. Example: `(heal >= 1 or tank >= 1) and dps <= 1`
- Text: `name:"abc"`, `dungeon:"razor"`, `comment:"fast"`, `class:"mage"`, `state:"relaxed"`.
- A mistake in the text is shown in red with its position, and all rows stay visible until it is fixed.
- Save your own filters under a name and pick them from the list. A few useful ones come with the addon (Need a healer, Need a tank, Room for a DPS...).

## Message in one click

The **Msg** button whispers the leader with your template. Default: `{class} {level} LFG {dungeon}`

- Wildcards: `{class}` `{level}` `{role}` `{dungeon}` `{leader}` `{spec}`. A preview shows the result as you type.
- At most one message per second, so a double click does not send twice.
- **Custom** opens a whisper to the leader that already starts with your own beginning (default `{class} {level} `, same wildcards): type the rest and press Enter.
- **Invite** works for solo players looking for a group (when you are alone or the leader of your group). Groups are contacted with Msg.

## Options

- Message template and the beginning of the Custom message.
- Window scale, font (any LibSharedMedia font), font size, outline, row height, visible columns, default category.
- Profiles: each character has its own by default; copy, reset, export and import as text.
- Optional side tab on the game's group finder window that opens Free LFG, and a minimap button.

## Commands

- `/flfg` — open the table
- `/flfg help` — short help

## Free Hub

Free LFG works on its own. With **Free Hub** installed, it opens inside the hub next to the other Free addons, and a single minimap button replaces theirs.

**Want more fonts?** Install [SharedMedia Additional Fonts](https://www.curseforge.com/wow/addons/shared-media-additional-fonts) (or any LibSharedMedia font pack): its fonts appear automatically in the font list.

## Notes

- Built for WoW Forever. The game only lets an addon start a search from a click, so searching is always done with the **Refresh** button.
- Free LFG does not change how the game's finder works: it only reads its results and adds an optional side tab to its window.
- Bug reports and ideas are welcome in the comments.
