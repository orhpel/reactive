# 05 — Replacing Your Event Bus, or "Just Declare What You Care About"

**Shows off:** `effect()`, `effectScope()`, and why "callback soup" stops
being a valid architecture at scale  
**Difficulty:** ⭐⭐⭐  
**Why you'd use this:** You've built a global event bus and now nobody
knows who fires what, when, or in what order.

## The premise

You have three components:

- A **network layer** that receives messages and updates a shared
  `world` table.
- A **renderer** that draws whatever's in `world`.
- A **persistence layer** that flushes `world` to disk periodically.

The event-bus approach:

```lua
-- Don't do this.
bus.on("net:message",   function(msg)    world:update(msg)       end)
bus.on("world:updated", function()       renderer:redraw()       end)
bus.on("world:updated", function()       persistence:mark_dirty() end)
bus.on("tick",          function()       persistence:maybe_flush() end)

-- ...and somewhere else:
bus.on("world:updated", function()       -- added 6 months later,
  analytics.track("world_update")        -- forgotten in the docs,
end)                                     -- fires twice because someone
                                         -- else already wired this.
```

Every `bus.emit("world:updated")` is a leap of faith. You don't know
how many subscribers there are, what they do, or what order they fire
in. You *certainly* don't know why the renderer sometimes redraws four
times per frame.

## With `reactive.lua`

```lua
local reactive = require("reactive")
local _reactive = reactive.reactive
local effect    = reactive.effect
local watch     = reactive.watch

local world = _reactive({ entities = {}, tick = 0 })

-- Renderer: tracks exactly what it reads.
effect(function()
  render(world.entities, world.tick)
end)

-- Persistence: tracks the subset of `world` it cares about.
watch(
  function()
    -- Return the slice we care about. The watcher tracks this getter's reads.
    local slice = { entities = {} }
    for id, e in pairs(world.entities) do
      slice.entities[id] = { x = e.x, y = e.y, hp = e.hp }
    end
    slice.tick = world.tick
    return slice
  end,
  function(snapshot)
    queue_flush(snapshot)
  end
)
```

## The point

The renderer and the persistence layer **both subscribe to `world`**,
but they subscribe to **different slices of it** — because they read
different fields. If `world.entities[id].hp` changes but `world.tick`
doesn't:

- The renderer fires (it reads `entities`).
- The persistence watcher fires (its getter reads `hp`).
- If you had a "tick counter" effect that only reads `world.tick`, it
  wouldn't fire.

Compare to the event bus, where the only granularity available is "I
emitted `world:updated` — everybody who has that string, react."

## Why this matters when you scale

The event bus works for five events and three subscribers. It stops
working when:

- A new subscriber needs to know **what specifically changed**, and the
  bus only broadcasts "something changed."
- Two subscribers depend on each other's output, and the firing order
  becomes load-bearing (it always does, and it's never documented).
- Someone writes `bus.emit("world:updated")` **without** actually
  updating `world`, and now every subscriber is confused.
- Someone else writes `world.x = 5` **without** emitting, and now
  half the system is stale.

`reactive.lua` fixes the last two by construction: **changes go through
the reactive proxy, or they don't count.** There is no `world.x = 5`
that bypasses the tracking — unless you `markRaw()` the table, and then
you've explicitly opted out.

## When to still use an event bus

- **Cross-process events.** Reactivity is single-process, in-memory.
  You can't `ref()` a network message.
- **One-shot events with no state** — "user clicked the button." There's
  nothing to *be reactive about*; it's a fact, not a state change. (Or
  model it as `click_count = ref(0)` and let subscribers react to that.
  Both work.)
- **Broadcasting to an unbounded audience** where subscriber identity
  doesn't matter. Reactivity tracks *who read what*; if you truly don't
  care, you're not gaining much.

For everything else — **push state, not events.** Let the framework
figure out who cares.

## Reference

- [`effect()`](../02-ref-and-effect.md) — auto-tracking side effects
- [`watch()`](../05-watch.md) — invoking a callback on change; covers getter-function sources (used above for the "slice the state" pattern)
- [`reactive()`](../04-reactive-objects.md) — deep proxy for plain Lua tables
- [`markRaw()`](../04-reactive-objects.md) — explicitly opting a table out of wrapping (the "just don't track this" escape hatch)
- [Iteration details](../11-iteration-details.md) — what `pairs()` and `#` actually trigger (relevant because the watch getter above iterates `world.entities`)

→ **Next:** [06-lazy-derived-graph.md](06-lazy-derived-graph.md)