# RTSC — RTS control

RTSC lets you command playerbots like an RTS: mark a spot on the ground and send bots there.
It spans three layers — `mod-playerbots` (the behaviour), `mod-multibot-bridge` (the transport),
and this addon (the bar). This document records how the three fit together, because the model is
not obvious from any one of them.

## The one thing to understand

**No command carries coordinates.** The only way a world position reaches a bot is a real
ground-targeted cast of **spell 30758** by the master. Playerbots renames that spell to `aedm`
(`data/sql/world/updates/2025_08_27_03.sql`), hooks the master's `CMSG_CAST_SPELL`
(`Playerbots.cpp`, `OnPacketReceived`), and reads the destination in
`SeeSpellAction::Execute`, storing it as the AI value `see spell location`.

Every `rtsc …` command therefore does one of three things:

1. **arms** what the *next* ground cast will do (`move`, `save <name>`, `save selected <name>`),
2. **replays** an already stored point (`go <name>`, `last`),
3. **manages** selection or storage (`select`, `cancel`, `toggle`, `show`, `unsave`, `reset`,
   `save here`).

This is why every casting button in the bar is a `SecureActionButtonTemplate` carrying
`/cast <aedm>`: the addon cannot obtain a terrain coordinate, so the *client* must place it.
The macro text is built from `GetSpellInfo(30758)` rather than the literal string `aedm`, so a
client whose `Spell.dbc` names 30758 differently still works. If `GetSpellInfo(30758)` returns
nil the client is missing the spell entirely and RTSC cannot work at all.

## Marquee select

With **nothing armed**, a ground cast is a rubber-band selection (`SeeSpellAction.cpp`):

- bots within 10 yards of the click become **selected**,
- bots outside become **deselected**,
- bots that were *already* selected **move** to the click, with their formation offset applied.

So the ordinary loop is: click a role button (which selects and opens the reticle) → click the
ground → they go. No selection command is needed for the proximity case at all.

## The command surface (all 13 sub-forms)

| Sub-command | Effect |
|---|---|
| *(bare)* | Trains the master's `aedm` spell. Sent by the addon as `enable`. |
| `select` / `cancel` / `toggle` | Selection flag, with a spell visual on the master's client. |
| `reset` | **Destructive**: wipes every saved location on every bot *and* untrains the spell. |
| `move` | Arms persistent move mode — every later cast moves the bot, until `cancel`/`reset`. |
| `save <name>` | Arms a save; the point is captured on the next cast. |
| `save selected <name>` | Same, but only bots whose `RTSC selected` flag is set. **The bar no longer uses this** — see below. |
| `save here <name>` | Stores each bot's **own current position** immediately — a formation snapshot. |
| `unsave <name>` | Drops one saved location. |
| `go <name>` | Moves to a saved location (exact point, no formation offset). |
| `last` | Moves to the most recent cast position, **with** formation offset. |
| `show` / `show <name>` | Lists saved names by whisper / summons a 2-second marker at one. |

Playerbots matches these with `find(...) != npos` but slices arguments with fixed `substr()`
offsets, so a token that is not an exact prefix yields a garbage name. The bridge rebuilds every
command from validated tokens (`NormalizeRTSCCommand`) to keep that unreachable.

The `rtsc` **strategy is a no-op** — `RTSCStrategy::InitTriggers` is empty and the gate in
`SeeSpellAction.cpp` is commented out. Nothing needs enabling; the root button's
`co +rtsc,+guard,?` is kept only in case that gate is ever restored.

Security is effectively **master-only**, and `RTSCAction` requires `GetMaster()` — an ungrouped
bot ignores RTSC entirely.

## Transport

Bridge-first, exactly like the rest of the addon. `UI/MultiBotRTSCUI.lua` routes everything
through one local `sendRtsc(sub, tag)`:

- **Bridge:** `Comm.RunRtscCommand("ALL", "", "<tag> <sub>")` → `RUN~RTSC` → `RTSC_ACK`.
- **Fallback:** `MultiBot.ActionToGroup("<tag> rtsc <sub>")` (party/raid chat), used only when
  the bridge is down. `here` and `persist` have no chat equivalent and report that.

`tag` is a playerbots chat filter (`@tank`, `@group1-3`, …). These are applied inside
`PlayerbotAI::HandleCommand`, which the bridge's silent-whisper path goes through — so the same
filters work over the bridge as over party chat.

Four sub-commands exist only on the bridge:

- **`persist`** — flushes the bot's context to the playerbots DB. Necessary because an armed
  `save` lands inside `SeeSpellAction` (invisible to the bridge) and context writes are memory
  only until `PlayerbotRepository::Save` runs. Without it, saved spots die on bot relog.
- **`here`** — seeds `see spell location` with the requester's position, then replays it via
  `rtsc last`. "Regroup on me, in formation", with no cast. It cannot be scoped with an `@tag`,
  because the native write happens before playerbots' chat filter runs.
- **`lock` / `unlock`** — set playerbots' `RTSC selection locked` flag, which stops a plain cast
  from rewriting the selection. See "The marquee no longer eats your selection" below. Like `here`
  they are applied natively and therefore cannot be `@tag`-scoped.

## The `see spell location` setter bug (server-side, fixed 2026-08-19)

`here` and `last` are the only two RTSC paths that read the AI value `see spell location`;
everything else uses the position from the cast packet directly, or `RTSC saved location`.
Both were broken, and they were broken in mod-playerbots, not here:

`SeeSpellLocationValue` is a `LogCalculatedValue`, so it inherited
`MemoryCalculatedValue<T>::Set()` — which **discards its argument**:

```cpp
void Set([[maybe_unused]] T value) override
{
    CalculatedValue<T>::Set(this->value);   // re-sets the member to itself
    UpdateChange();
}
```

So neither `SET_AI_VALUE(WorldPosition, "see spell location", …)` in `SeeSpellAction` nor the
bridge's `ApplyNativeRTSCHere` ever wrote anything. The value stayed default-constructed —
`MAPID_INVALID`, `0/0/0` — and `WorldPosition::operator bool()` returns **true** for it
(`GetMapId() != 0`), so `rtsc last`'s `if (spellPosition)` guard let it through.
`SetFormationOffset` then computed `(0,0,0) - masterPos + formationSlot`, i.e. the master's
position mirrored through the world origin: the bots ran thousands of yards the wrong way.
That is the "Regroup on me sends them somewhere else" symptom.

**Fix:** a narrow `Set` override on `SeeSpellLocationValue`
(`mod-playerbots/src/Ai/Base/Value/RTSCValues.{h,cpp}`) — additive, RTSC-only, and it repairs
`Last` at the same time. **Needs a worldserver rebuild.** The addon needed no change: it only
ever sends `here`.

## State

`GET~RTSC` streams `RTSC_BEGIN` / `RTSC_ITEM~<bot>~<token>~<selected>~<armed>~<names>` /
`RTSC_END`. `Core/MultiBotComm.lua` folds it into:

```lua
MultiBot.bridge.rtsc = {
    bots     = { [name] = { selected = bool, armed = "save 3", slots = { ["3"] = true } } },
    slots    = { ["3"] = true },  -- aggregate: any bot has this slot
    selected = 4,                 -- count, shown in the root button's tooltip
    stamp    = <time>,            -- set only once a stream has completed
}
```

`stamp` is what makes a connected-but-never-queried bridge fall back to the addon's own optimistic
bookkeeping instead of blanking the bar.

The slot faces render from this, not from click bookkeeping: clicking an empty slot only *arms* a
save, and the slot fills only after `UNIT_SPELLCAST_SUCCEEDED` for the marker spell is followed by
a fresh `GET~RTSC`. Escaping the reticle therefore leaves the slot empty, as it should.

Selection is reported as a **count in the root button's tooltip**. It is deliberately not painted
onto Units roster buttons — a unit button's `state` is its online/offline flag and must not be
repurposed.

## Selection: one concept, replace by default

The selection is a **server-side per-bot flag** (`RTSC selected`). Two things about it are
invisible from the bar, and together they were why role buttons behaved randomly — sometimes
moving the tanks, sometimes the whole raid, sometimes an arbitrary part of it:

1. **`rtsc select` is purely additive.** `RtscAction` only ever sets the flag *true*; nothing
   ever clears it for anyone else. Clicking Tanks and then DPS left **both** selected.
2. **A plain ground cast replaces the whole selection.** `SeeSpellAction`'s marquee branch does
   `SET_AI_VALUE(bool, "RTSC selected", inRange)` for *every* bot, where `inRange` is "within 10
   yards of the click". So one cast silently discards a role selection and leaves a proximity
   blob behind — which the next role click then added to.

On top of that the bar kept a *second*, local selection (`selectorFrame.selector`) that could
disagree with the server's: left-clicking a role cleared the local list but sent nothing to
clear the server's, `Last`/`go` scoped by the local list while **`Move` ignored it entirely**,
and the spot buttons used it only as a boolean to pick `save selected` over `save`.

The bar now drives one explicit model:

| Action | Meaning |
|---|---|
| Role/group, **left** | Select **only** this tag: sends `cancel`, then `<tag> select`, then casts |
| Role/group, **right** | **Toggle** this tag: `<tag> select`, or `<tag> cancel` to deselect just it |
| `@all`, left / right | Select everyone and drop role scoping (untagged `select` already reaches all) |
| Browse, **right** | `cancel` — clear the selection on both sides |
| Root, **left** | Cast the marker and nothing else — the "send" button for the current selection |

The selection **persists across actions**: sending the same group to spot 1 and then spot 2 no
longer needs re-selecting, and nothing clears it behind your back. `Move` is scoped like `Last`
and the spot buttons; with nothing selected it still means everyone.

Lit selector buttons are what *you asked for*; the **number on the root button** is what the
server reports (`GET~RTSC`'s `selected` count), re-read shortly after every selection change.
When the two disagree, the badge is right.

### Why the bar never sends `save selected`

`save selected <n>` looks like the natural fit for "store this spot for the selected bots", and the
bar used to send it (untagged) whenever anything was selected. It leaves the scoping to the
server's per-bot `RTSC selected` flag — **the same flag a plain marker cast overwrites** with "was
within 10 yards of the click". So after any ordinary send, the flag was typically empty, the save
landed on nobody, and the slot stayed grey until a bot happened to be selected again.

Slot saves are therefore scoped the same way as `go`/`last`/`move`: through the chat filter
(`@tank save 4`), which reaches exactly the bots the bar says are selected regardless of what the
flag currently holds.

### The marquee no longer eats your selection

With nothing armed, a cast does two things: it moves every selected bot to the click, **and** it
replaces every bot's flag with "was within 10 yards of it" (`SeeSpellAction.cpp`). That second part
is upstream rubber-band selection, and it is why sending the tanks somewhere *deselected the tanks*
(they are far from the click by definition) and *selected the bystanders* standing at the
destination — who then got dragged along by the next cast, while the count badge and the "send
selected" button disagreed about who was involved.

**The fix is a lock, server-side** — the AI value `RTSC selection locked`
(`mod-playerbots/src/Ai/Base/Value/RTSCValues.h`, gated in `SeeSpellAction.cpp`), set through the
bridge's `lock` / `unlock`. While it is set, a plain cast still moves every selected bot but writes nobody's flag, so the bar's
selection is exactly what moves, every time. The bar locks whenever its selector is non-empty and
unlocks when it empties — with no explicit selection the rubber-band *is* the intended behaviour,
and upstream's is what you get. The flag defaults false and is not persisted, so the bar re-sends it
on panel open and on every root-button click (a bot summoned since the last selection change would
otherwise still rubber-band itself in).

**A client-side repair alone cannot fix this**, which is why the earlier attempt only worked
sometimes. The cast is queued into each bot's `masterIncomingPacketHandlers` when the master's
`CMSG_CAST_SPELL` arrives; the addon's repair can only be sent a client round-trip later, and
`PlayerbotAI::UpdateAIInternal` drains `HandleCommands()` **before** the master packet queue. So for
every bot that has not ticked in that window the repair is applied first and immediately overwritten
— and since each bot ticks on its own `nextAICheckDelay`, the result was a random subset repaired.

The repair is still there as the fallback for a worldserver without the lock, but rebuilt around
that ordering:

- it fires at `RTSC_CAST_SETTLE + 0.25s`, once the marquee has certainly landed, not at cast time;
- it then **verifies**: `GET~RTSC` reports the selected flag per bot, so the bar compares the set the
  server has against the set it recorded right after the last deliberate selection change, and
  repeats the re-assert (at most twice) if they differ;
- it is skipped entirely when the lock is in force, and when nothing is explicitly selected.

**Needs a worldserver rebuild** (`MODULES/mod-playerbots` + `MODULES/mod-multibot-bridge`). Until
then the fallback runs, and support is auto-detected rather than configured: an old playerbots has
no such value, so the bridge acks `lock` with `executed = 0`; an older bridge rejects the
sub-command in `NormalizeRTSCCommand` and acks with an *empty* command. Both switch the bar to the
fallback, and neither is reported to the user — it is a probe, not a click.

Casts that had a save or `move` armed skip the marquee branch entirely, so they need neither.

### Slot feedback

`UNIT_SPELLCAST_SUCCEEDED` for the marker is proof the cast happened, so an armed slot is shown as
filled immediately instead of waiting ~1.5s for `GET~RTSC`. The optimistic fill is dropped the
moment real state arrives, so a save that genuinely did not land goes back to empty rather than
lying. Escaping the reticle fires no event and therefore fills nothing.

### Selecting is not sending

Right-clicking roles only builds the selection; **nothing on the bar moves a bot by itself**. The
move happens when the master casts the marker and clicks the ground: with nothing armed,
`SeeSpellAction` moves every bot whose flag is set to that point. So the loop is

> right-click the roles you want → **left-click the root RTSC button** → click the ground.

That is why the root button must not touch the selection: it is the only control that casts without
changing who is selected. (A role's *left*-click is the one-role shortcut — select only them and
cast, in a single click.) `Last` and the filled spot buttons replay a stored point instead, so they
need no cast at all.

One consequence worth knowing: `cancel` also clears `RTSC next spell action`, so changing the
selection **disarms a pending `move` or `save`**. Select first, then arm — the Move button's lit
state follows `anyBotArmed("move")`, so it visibly turns off if this happens.

## Spot slots that will not clear (server-side, fixed 2026-08-19)

Slots reported as occupied when nothing was ever saved in them — and `unsave` appearing to do
nothing — is the **same `WorldPosition::operator bool()` trap** as the `here` bug. The bridge
decided a slot was filled with:

```cpp
if (!saved || !saved->Get())   // "the same test rtsc show uses"
    continue;
```

`operator bool()` is `mapId != 0 || x/y/z != 0`, and a default-constructed `WorldPosition`
carries `MAPID_INVALID` (`0xFFFFFFFF`) — so it reads as a **real** location. `RTSC saved
location` values are created on first access by name, and `RESET_AI_VALUE2` (what `unsave`
runs) restores exactly that truthy default. Net effect: any slot the bots had ever touched
reported as filled for ever, and clearing one was impossible.

`SendRtscPackets` now tests for a *usable* position instead — a real map id and not all-zero
coordinates. **Needs a worldserver rebuild** (`MODULES/mod-multibot-bridge`).

## The bar

Left of centre: nine location slots (`MACRO<i>` when empty, `RTSC<i>` when filled, same position).
Right of centre: group/role selector buttons, `@all`, Browse, then Move / Last / Here. Two hairline
separators mark the three blocks (spots · selection · actions).

Each slot carries its **number** on the face — grey digits when empty, gold when a spot is stored.
Both faces use the same icon and the same position, so without the digit there is nothing to tell
slot 3 from slot 7.

| Control | Action |
|---|---|
| Root, left | **Send**: open the reticle; the ground click moves the current selection there |
| Root, right | `enable` (train the spell) + `co/nc +rtsc,+guard` |
| Root, **shift+right** | `reset` — wipes all saved locations, clears all nine slots |
| Empty slot, left | Arm `save <i>`, scoped to the selection (`@tank save <i>`) + reticle |
| Empty slot, **shift+left** | `save here <i>` — formation snapshot, no cast |
| Filled slot, left | `go <i>` |
| Filled slot, **ctrl+left** | `show <i>` — summon a 2-second marker there |
| Filled slot, right | `unsave <i>` |
| Role/group, left | Select **only** this tag (`cancel` + `<tag> select`) + reticle |
| Role/group, right | **Toggle** this tag: `<tag> select`, or `<tag> cancel` if already selected |
| `@all`, left / right | `select` for everyone, dropping role scoping (left also opens the reticle) |
| Browse, left / right | Swap role↔group row / `cancel` (deselect everything) |
| Move, left / right | Arm `move` for the selection + reticle / clear the selection |
| Last, left / right | `last` / re-read state from the bridge |
| Here, left | `here` (bridge only; hidden when the bridge is down) |

`/mb help rtsc` prints this table in game.

Left and right differ on the secure buttons even when they send the same command: only `type1` is
set, so **only left-click casts**. Modified clicks set an empty `shift-type1` / `ctrl-type1` so
they do not open a reticle the action does not want.

**Closing the bar sends `cancel`, never `reset`.** The old behaviour wiped every saved location
and untrained the master's spell every time the panel was closed. `cancel` drops the selection
server-side, so closing now clears the bar's lit tags and releases the lock with it — otherwise
re-opening showed a selection no bot was part of any more.

## Reading the bar's state

Three things the bar reports, all of which used to be invisible and made RTSC look broken rather
than un-set-up:

- **Marker spell not learned** (`IsSpellKnown(30758)` false) — every control that only means
  something *followed by a ground cast* is faded to 35% alpha, the root button greys, and its
  tooltip carries the fix in red. Alpha is deliberately not `setDisable()`: the slot buttons
  already use desaturation for empty-vs-filled and that meaning has to survive. Attempting one of
  the arming sub-commands (`select`, `move`, `save <n>`, `save selected <n>`) also prints the hint.
- **A command reached no bot** — `RTSC_ACK` has always carried `executed`, and the addon used to
  discard the whole payload. `MultiBot.OnRtscCommandApplied(command, executed)` now reports a zero
  (throttled per command kind). Same treatment for `POSITION_ACK`
  (`MultiBot.OnPositionCommandApplied`), which previously stayed silent when disperse applied to
  nobody.
- **The pending selector** — the accumulated `@tag` list from right-clicks appears in the root
  button's tooltip next to the selected-bot count.

`Browse` tracks which row it shows in `browseButton.showingGroups`, **not** in `button.state`:
`state` is the engine's enable/desaturation flag, and writing it raw left the button's appearance
permanently out of step with its logical state.

Opening the panel retries `GET~RTSC` until the bridge answers (5 tries, 0.75 s apart). A single
request could lose the race with the handshake, and the bar then rendered empty slots from local
bookkeeping — indistinguishable from "my saved spots are gone".
