# reactive.lua

> **Vue 3's reactivity system, ported to Lua 5.4.** No virtual DOM, no
> component tree, no build step. Just dependency tracking that actually
> works.

[![Lua](https://img.shields.io/badge/Lua-5.4-blue?logo=lua)](https://www.lua.org/)
[![Tests](https://img.shields.io/badge/tests-passing-success)](#)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](#)
[![Vibe](https://img.shields.io/badge/vibe-immaculate-purple)](#)

## Why does this exist?

You know that moment when you're writing Lua and you think:

> "I just need a number that some other thing watches, and when the
> number changes, the other thing should notice. That's it. That's the
> whole requirement."

And then you spend the next four hours building an observer system,
manually invalidating caches, forgetting to detach listeners, and
debugging a subtle bug where an event fires twice because you subscribed
it twice and neither subscription knows about the other.

**This library is that thing you should have used instead.**

`reactive.lua` is a faithful, non-`__DEV__`-polluted port of Vue 3's
`@vue/reactivity` package: the same Dep/Link graph, the same EffectFlags
bitfield, the same computed caching semantics — just without the
JavaScript, without the build tooling, and without a virtual DOM you
never asked for.

You get:

- `ref()` and `computed()` — values that know when they change
- `reactive()` — tables that know when they're mutated
- `effect()` — functions that re-run when their dependencies change
- `watch()` / `watchEffect()` — you know, watchers
- `effectScope()` — disposal groups so you can stop everything at once
- `shallowRef()`, `shallowReactive()`, `readonly()`, `shallowReadonly()` —
  all the variant flavors, because sometimes "deep" is the wrong answer
- Tracking controls (`pauseTracking` / `enableTracking` / `resetTracking`)
  for the 3% of cases where automatic dependency collection is *too
  eager*

## What it isn't

- **Not a game engine.** No scene graph, no ECS, no rendering loop.
- **Not a GUI framework.** Pure reactivity core. If you want a renderer,
  that's a future project.
- **Not magic.** Everything is synchronous, predictable, and debuggable
  with `print()`. If something fires twice, there's a reason — you'll
  find it.

## Show me something

```lua
local reactive = require("reactive")

-- A plain old ref. Nothing fancy.
local count = reactive.ref(0)

-- A computed that depends on it. Lazily evaluated, cached, re-runs only
-- when `count` actually changes.
local doubled = reactive.computed(function() return count.value * 2 end)

-- An effect that reads both. Runs once immediately, then again on every
-- change — but only if `doubled` actually changed. It won't, unless
-- `count` did. Caching! It's a thing!
reactive.effect(function()
  print(("count=%d doubled=%d"):format(count.value, doubled.value))
end)

count.value = 5   -- prints "count=5 doubled=10"
count.value = 5   -- nothing happens. `count` didn't change. Good.
count.value = 7   -- prints "count=7 doubled=14"
