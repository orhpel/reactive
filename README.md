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
local ref      = reactive.ref
local computed = reactive.computed
local effect   = reactive.effect

-- A plain old ref. Nothing fancy.
local count = ref(0)

-- A computed that depends on it. Lazily evaluated, cached, re-runs only
-- when `count` actually changes.
local doubled = computed(function() return count.value * 2 end)

-- An effect that reads both. Runs once immediately, then again on every
-- change — but only if `doubled` actually changed. It won't, unless
-- `count` did. Caching! It's a thing!
effect(function()
  print(("count=%d doubled=%d"):format(count.value, doubled.value))
end)

count.value = 5   -- prints "count=5 doubled=10"
count.value = 5   -- nothing happens. `count` didn't change. Good.
count.value = 7   -- prints "count=7 doubled=14"
```

Not convinced? Here's `reactive()`:

```lua
-- `reactive.reactive` shares its name with the module itself, so we
-- alias it locally. Any other name works — `_reactive`, `r`, `makeReactive`.
local _reactive = reactive.reactive

local state = _reactive({
  user = { name = "Lephro", roles = { "admin" } },
  ui   = { theme = "dark", fontSize = 14 },
})

effect(function()
  print(("theme: %s"):format(state.ui.theme))
end)

state.ui.theme = "light"    -- effect re-runs
state.ui.fontSize = 16      -- does NOT re-run (effect never read it)
```

That last line is the whole point: the effect tracks **exactly** what it
reads, freshly discovered on every run. No "subscribe to the whole
object and hope for the best."

## Do you have more?

Yes. In the [documentation](https://orhpel.github.io/reactive/) you'll find:

- [ref() and effect()](https://orhpel.github.io/reactive/02-ref-and-effect/) — the intro
- [computed()](https://orhpel.github.io/reactive/03-computed/) — lazy, cached, chainable
- [reactive()](https://orhpel.github.io/reactive/04-reactive-objects/) — deep proxies for your tables
- [watch() and watchEffect()](https://orhpel.github.io/reactive/05-watch/) — with the full `deep`
  option spec
- [Deep watching](https://orhpel.github.io/reactive/09-deep-watching/) — why `deep = N` means what
  it means
- [Iteration details](https://orhpel.github.io/reactive/11-iteration-details/) — what `pairs()`,
  `#`, and `ipairs()` actually trigger
- [Tracking control](https://orhpel.github.io/reactive/12-tracking-control/) — the pause/enable/
  reset trio
- [effectScope()](https://orhpel.github.io/reactive/08-effect-scope/) — disposal groups

…and a [`examples/`](https://orhpel.github.io/reactive/examples/) folder with
**runnable, real-world-shaped examples** showing the library in action
beyond toy counters. More are landing as the project grows.

## How does it compare to Vue's version?

Feature | Vue 3 | reactive.lua
--- | --- | ---
`ref` / `computed` / `effect` | ✅ | ✅
`reactive` / `readonly` / `shallow*` | ✅ | ✅
`watch` / `watchEffect` | ✅ | ✅
`effectScope` | ✅ (nested) | ✅ (flat only — [see why](https://orhpel.github.io/reactive/08-effect-scope/))
`toRef` / `toRefs` / `proxyRefs` | ✅ | ✅
Collection handlers (`Map`/`Set`/etc.) | ✅ | ❌ (Lua has one table type)
`customRef`, SSR helpers | ✅ | ❌ (not implemented)
Virtual DOM, components, templates | ✅ | ❌ (never will be)

The reactivity core is intentionally **faithful**; the framework around
it is intentionally **absent**.

## Installation

Copy the `reactive/` directory into your project. That's it. No luarocks
manifest, no build step, no dependency hell. It's pure Lua 5.4.

```lua
local reactive = require("reactive")
```

If you need type hints for your editor, the `.d.lua` files are already
in place next to their modules. Point LuaLS at them (or just open the
folder — they're auto-detected).

## Requirements

- **Lua 5.4** (uses native `&`, `|`, `<<` bitwise operators)
- No external dependencies

## Contributing

Open an issue, open a PR, send a carrier pigeon. The docs in
[docs/](https://orhpel.github.io/reactive/) explain the design decisions and where the
deliberate divergences from Vue are — read them before proposing
"improvements" that break the design intent.

## License

MIT. Do whatever you want, just don't blame us if your refs get stuck
in a dependency cycle. (They won't. But still.)

---

_If this library saved you from writing yet another observer pattern by
hand: you're welcome. Go build something with it._
