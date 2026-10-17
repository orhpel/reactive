# 01 — The Reactive Counter (That Isn't Really About Counters)

**Shows off:** `ref()`, `computed()`, `effect()`  
**Difficulty:** ⭐  
**Why you'd use this:** You're tired of manually calling `update_ui()`
every time you touch a variable.

## The premise

You have some state. Something else cares about that state. Right now,
"something else" is a `print()` — later it'll be a render call, a
network sync, a save-file flusher, or (let's be honest) a `print()`.

Traditional Lua:

```lua
local count = 0
local doubled = 0

local function bump()
  count = count + 1
  doubled = count * 2
  print(("count=%d doubled=%d"):format(count, doubled))
end

bump()  -- works
bump()  -- works
count = 99  -- 💥 `doubled` is now stale and nothing printed
```

That last line is the bug that ships. Someone, somewhere, sets `count`
directly instead of going through `bump()`, and now `doubled` is a lie
and the UI is showing numbers from a parallel universe.

## With `reactive.lua`

```lua
local reactive = require("reactive")
local ref      = reactive.ref
local computed = reactive.computed
local effect   = reactive.effect

-- A ref is just "a value that other things can watch."
local count = ref(0)

-- A computed is "a value that watches other values and caches its
-- result."
local doubled = computed(function()
  return count.value * 2
end)

-- An effect is "a function that re-runs whenever any ref or computed it
-- read has changed."
effect(function()
  print(("count=%d doubled=%d"):format(count.value, doubled.value))
end)

-- Now the only way to change `count` is to actually change it.
-- Everything downstream stays in sync. Automatically.
count.value = 1   -- prints "count=1 doubled=2"
count.value = 2   -- prints "count=2 doubled=4"
count.value = 2   -- nothing. count didn't change. Good.
count.value = 99  -- prints "count=99 doubled=198"
```

## What just happened

1. The `effect()` ran once, immediately, reading both `count.value`
   and `doubled.value`.
2. When the effect read `doubled.value` for the first time, the computed
   ran its own getter, which read `count.value`. So the computed became
   a *subscriber* of `count`.
3. When we set `count.value = 1`, that triggered every subscriber of
   `count`: the effect (direct subscriber) and the computed (which then
   invalidated `doubled`, which triggered the effect again through the
   computed's own dep).

You didn't wire any of that. The tracking machinery did.

## Why this matters

The classic Lua answer to this problem is:

> "Just don't forget to update `doubled` every time you update `count`."

That works for six weeks. Then someone joins the team, writes a new
feature, updates `count` in a place you never saw, and your UI is
silently wrong for a month.

`reactive.lua` makes "forgetting" **structurally impossible** — because
there's nothing to forget. The dependency graph re-discovers itself
fresh on every run.

## Try it

Change the effect to *also* print the number of times it's run:

```lua
local runs = 0
effect(function()
  runs = runs + 1
  print(("[run %d] count=%d doubled=%d"):format(runs, count.value, doubled.value))
end)
```

Note that `runs` is a plain Lua local, **not** a ref. Writing to it does
not re-trigger the effect. That's important: **only reactive values
trigger**, and only the ones the effect actually read. Plain variables
stay plain.

## Reference

- [`ref()`](../02-ref-and-effect.md) — a reactive value with a `.value` field
- [`computed()`](../03-computed.md) — lazy, cached, dependency-tracked derived values
- [`effect()`](../02-ref-and-effect.md) — re-run a function whenever its reads change

→ **Next:** [02-shopping-cart.md](02-shopping-cart.md)