# CLAUDE.md — MultiBot addon directives

Directives for working in `CLIENT_ADDONS/MultiBot` (the **client-side**, bridge-first WoW 3.3.5a UI for
AzerothCore **mod-playerbots**). Detailed reference lives in the **`multibot-addon` skill**
(`.claude/skills/multibot-addon/`); Lua-5.1 client-dialect rules are in the **`wotlk-335a-lua`
skill**. Also see `AGENTS.md`, `README.md`, `TODO.md`, and `docs/` here.

## Read before editing
1. The `multibot-addon` skill: `SKILL.md` → `references/architecture.md` →
   `references/working-notes.md`.
2. For a feature you're changing, its docs in `docs/` and the relevant `TODO.md` entries.

## How this addon works (1 paragraph)
It's **bridge-first**: `MultiBot.Comm` sends `GET~…`/`RUN~…` over addon messages to the
`mod-multibot-bridge` server module; replies fill `MultiBot.bridge` caches (`.connected`,
`.roster`, `.states`, `.details`, …) that the UI reads. The bot list is `MultiBot.index`
(`players`/`actives`/`members`/`friends`/`favorites` + `classes`); each bot has a unit button
(`units.buttons[name]`) and, when online, an EveryBar action row (`units.frames[name]`).

## Online vs offline (the recurring bug area — handle with care)
A unit button's `state` is its online flag **and** its desaturation: `setEnable()` = bright
(`state=true`), `setDisable()` = greyed (`state=false`); the EveryBar shows only when
`state==true`; new buttons default to `state=true`. **The authority for `state` differs per
Units view:**
- **Players** (bridge bots) → `IsBridgeRosterBotActive(name)` (in your party/raid **and**
  `UnitIsConnected` — a group slot keeps the name after a bot logs out, so name-only matching
  shows offline bots as online). Applied by `SyncBridgeRosterToPlayers` **and**
  `ApplyBridgeBotState` — the latter must mirror it and **never blanket-enable** (states are
  reported for the whole pool).
- **Guild** → `GetGuildRosterInfo(i)` 9th return (`online`); **Friends** → `GetFriendInfo(i)`
  5th return (`connected`). Set `button.state` from these or every member shows online.
- `getDisplayableUnits` must keep a **deterministic order** (online-first, then alphabetical) or
  pagination scrambles and offline bots appear online when scrolling.

## Non-negotiable directives
1. **Verify**: run luacheck from this folder (`& $env:TEMP\luacheck.exe <files> --codes`, reads
   `.luacheckrc`) — `0 warnings / 0 errors`. No `luac` on PATH; download/`luaparser` fallback in
   the skill's working-notes. Target **Lua 5.1**.
2. **Minimal diffs**, match local style; return real-line-break diffs with file paths (`AGENTS.md`).
3. **Deployment caveat**: this is the dev copy (`f:\D\DEV\CLIENT_ADDONS\MultiBot`). The game loads
   from the in-workspace client's `f:\D\DEV\CLIENT\world of warcraft 3.3.5a hd\interface\addons\MultiBot`
   (the dev copy is **not** auto-deployed there). If a fix "doesn't work," confirm the client copy
   has it (search for a comment marker from the change), then `/reload`. Fonts/`.toc` need a client
   restart.
4. **No automatic chat parsing** to refresh/populate UI — bridge-first only. Legacy chat is a
   diagnostic fallback gated by `MultiBot.allowLegacyChatFallback` (keep `false`). Keep the manual
   commands `who`, `co ?`, `nc ?`, `ss ?` working.
5. **Server is out of scope**: don't change command-syntax expectations or anything only fixable
   in `mod-multibot-bridge` / `mod-playerbots` (not in this workspace).
6. **Keep docs honest**: changing a wire message, DB assumption, event, or design decision means
   updating the matching doc (`DESIGN.md`/`README.md`/`TODO.md`) in the same change. Don't break
   the README HTML.
