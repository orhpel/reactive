# 04 — A Game Simulation Tick, or "Scoped Effects, Not Global Chaos"

**Shows off:** `effectScope()`, `effect()`, `watch()`  
**Difficulty:** ⭐⭐⭐  
**Why you'd use this:** You have transient subsystems (a battle, a
loading screen, a menu) that spin up state, react to it, and then need
to *stop* reacting when the subsystem ends. Manual cleanup is not a
strategy.

## The premise

You're building a small turn-based game. Each battle:

- Has its own `hp`, `mp`, `turn`, `status` state.
- Runs a `tick()` function on the game loop.
- Has subsystems that listen for changes: an HP bar renderer, a
  status-effect checker, a battle log writer.
- Should *completely stop* reacting when the battle ends.

Without `effectScope()`, you'd manually track every effect handle and
stop them all. Forget one and you leak; forget the wrong one and you
get a runtime error trying to render HP for a battle that ended ten
minutes ago.

## With `reactive.lua`

```lua
local reactive = require("reactive")
local _reactive   = reactive.reactive
local effect      = reactive.effect
local watch       = reactive.watch
local effectScope = reactive.effectScope

local function start_battle(party, enemies)
  local scope = effectScope()

  -- All effects created inside this `run` belong to `scope`.
  scope:run(function()
    local battle = _reactive({
      party   = party,
      enemies = enemies,
      hp      = {},
      mp      = {},
      turn    = 1,
      status  = {},
    })

    -- HP bar renderer: re-runs whenever any hp value changes.
    effect(function()
      for unit, hp in pairs(battle.hp) do
        render_hp_bar(unit, hp)
      end
    end)

    -- Status effect checker: reacts to status additions/removals.
    watch(function() return battle.status end, function()
      check_death_conditions(battle)
    end, { deep = true })

    -- Battle log: only logs on turn changes.
    watch(function() return battle.turn end, function(new_turn, old_turn)
      log(("turn %d → %d"):format(old_turn or 0, new_turn))
    end)

    -- Register the tick function as an effect too. Every tick, `turn`
    -- advances, statuses tick down, and the above watchers fire
    -- automatically. No manual dispatch.
    effect(function()
      tick_cooldowns(battle, battle.turn)
      tick_statuses(battle, battle.turn)
    end)
  end)

  return {
    battle = nil,  -- set by caller
    end_battle = function()
      -- This ONE call stops every effect/watch created above.
      -- HP bars stop rendering. Status checks stop running.
      -- The log writer stops logging. No leaks, no leftovers.
      scope:stop()
    end,
  }
end
```

## Why `effectScope` is the answer

Effects are great. Uncontrollable effects are not. Every `effect()`,
`watch()`, and `watchEffect()` created inside `scope:run(fn)` gets
registered to the scope. `scope:stop()` iterates them all and stops each
one — in the right order, with cleanup callbacks firing.

Compare to the manual version:

```lua
-- Don't do this.
local effects = {}
effects[#effects+1] = effect(render_hp_bars)
effects[#effects+1] = watch(...)
effects[#effects+1] = watch(...)
effects[#effects+1] = effect(tick)

-- Later:
for _, e in ipairs(effects) do
  e()  -- stop it
end
```

Every `effects[#effects+1]` you forget is a leak. Every scope you
*should* have created but didn't is a latent bug.

## The `turn` trick

Note that `tick_cooldowns` and `tick_statuses` are effect bodies — they
re-run whenever anything they read changes. But they read `battle.turn`,
which only changes when the caller mutates it:

```lua
battle.turn = battle.turn + 1  -- triggers everything that reads `turn`
```

So the game loop just does `battle.turn = battle.turn + 1` and the
whole battle state machine advances. The dependency graph does the
dispatch. You never write `dispatch_event("TURN_CHANGED", ...)`.

## When to reach for scopes

- **Transient subsystems** with a clear lifecycle (battles, dialogs,
  loading screens, editor sessions).
- **Test fixtures** — wrap each test in a scope, `:stop()` it in
  `afterEach`, and effects are guaranteed not to bleed between tests.
- **Plugin systems** — a plugin gets its own scope; unloading the
  plugin stops all its reactive effects.
- **Game state that reloads** — a new save file means a fresh scope,
  no need to track down every effect from the old one.

## What you *don't* get

Nested scopes (a scope inside a scope inside a scope) aren't
implemented — the scope implementation is deliberately flat. This isn't
"coming later"; it's a conscious design choice (see the design notes in
[`effectScope()`](../08-effect-scope.md) for the reasoning). If your
subsystem needs nested lifecycle, model it as a tree of scopes you
manage yourself:

```lua
local battle_scope    = effectScope()
local sub_scopes      = {}

local function start_phase(name)
  local s = effectScope()
  sub_scopes[name] = s
  battle_scope:run(function() s:run(function() ... end) end)
end
```

If you genuinely need nested scopes as a first-class feature, fork the
library and add them — the internals are commented and the design is
documented. Just don't expect upstream to grow them unless a concrete
project requirement shows up.

## Reference

- [`effectScope()`](../08-effect-scope.md) — collecting effects into a disposal group
- [`effect()`](../02-ref-and-effect.md) — auto-tracking side effects
- [`watch()`](../05-watch.md) — invoking a callback on change
- [`reactive()`](../04-reactive-objects.md) — deep proxy for plain Lua tables

→ **Next:** [05-event-bus-replacement.md](05-event-bus-replacement.md)