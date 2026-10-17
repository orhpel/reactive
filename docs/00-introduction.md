# Introduction

`reactive.lua` gives you Vue-3-style reactivity in plain Lua: values
that know when they've changed, and code that automatically re-runs
when the values it cares about do. No framework, no build step, no
dependencies — just `require("reactive")` and go.

Here's the smallest possible taste of it:

```lua
local reactive = require("reactive")
local ref = reactive.ref
local computed = reactive.computed
local effect = reactive.effect

local count = ref(0)
local double = computed(function() return count.value * 2 end)

effect(function()
  print("count is now", count.value, "double is", double.value)
end)

count.value = 5  -- prints "count is now 5 double is 10", automatically
```

That's the whole idea. Set a value, and everything that depends on it
just... updates. No manual "don't forget to call `updateUI()`" calls
scattered through your code, no bugs from forgetting one.

## Why does this exist?

This library started life as the foundation for an
[OpenComputers](https://www.curseforge.com/minecraft/mc-mods/opencomputers)
GUI project — a state-driven UI needs *something* to notice when the
underlying state changes, and reactivity systems are a genuinely good
answer to that problem. Rather than invent something from scratch, we
borrowed the design that's already been battle-tested by millions of
Vue apps.

## About the Vue connection

If you know [Vue 3](https://vuejs.org/), a lot of this will feel
instantly familiar — `ref`, `computed`, `reactive`, `watch` are all
here, doing roughly what you'd expect. That's on purpose: `reactive.lua`
is built on the same core ideas as Vue 3's `@vue/reactivity` package,
and full credit goes to the Vue team for the underlying design (the
dependency-tracking mechanism in particular is genuinely clever
engineering).

That said, this is **not** a mechanical port. It's a from-scratch
rewrite for a very different language: everything specific to
JavaScript/the DOM (Proxy traps, `Map`/`Set` reactivity, TypeScript's
type machinery, SSR handling) is gone, and a few things are
deliberately simplified because Lua — and this project's actual
needs — don't call for the full complexity Vue's ecosystem does. If
you're coming from Vue and something behaves differently than you'd
expect, check out [Where we differ from Vue](90-differences-from-vue.md)
— we've tried to flag the interesting cases as they come up, too.

If you've never touched Vue: don't worry about any of the above, none
of it is required knowledge. Just keep reading.

## Who built this

`reactive.lua` — code, tests, and this documentation — was built by
Lephro in collaboration with Claude (Anthropic). It's a decent proof
that you can build genuinely solid, well-tested software this way, so
we figured that was worth a mention. See [`NOTICE`](../NOTICE) for the
full credits, including the Vue.js copyright notice.

## What's next

Head to [Installation](01-installation.md) to get it into your
project, or jump straight to [`ref()` and `effect()`](02-ref-and-effect.md)
if you'd rather learn by example.
