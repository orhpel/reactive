# The `ref` family

`ref()` covers the common case. But every so often you'll hit a
shape of problem it's not quite built for — a value you don't want
deep-wrapped, a field you want to pull out of a `reactive()` table
without losing its reactivity, that sort of thing. This chapter is
for those moments.

## `shallowRef()` — when deep wrapping is overkill

`ref()` automatically wraps table values in `reactive()`, so mutating
into them is tracked. Most of the time that's exactly what you want.
But sometimes you're storing something big, or something that isn't
really "yours" to make reactive — a third-party object, a huge
dataset you're only ever going to *replace* wholesale, never poke at
field by field. That's `shallowRef()`:

```lua
local reactive = require("reactive")
local shallowRef = reactive.shallowRef
local effect = reactive.effect

local bigData = shallowRef({ huge = "dataset" })

effect(function()
  print(bigData.value)
end)

bigData.value = { totally = "new dataset" }  -- triggers, as normal
bigData.value.totally = "mutated in place"   -- does NOT trigger
```

Replacing `.value` wholesale still works exactly like a normal ref.
It's only *mutating into* the existing value that's untracked —
because that value was never wrapped in `reactive()` to begin with.
If you do need to notify subscribers after such an in-place mutation,
`triggerRef()` (see [`reference/ref.md`](reference/ref.md)) forces it
manually.

## `toRef()` — pulling a live link out of something

`toRef()` gives you a ref that stays linked to wherever it came from,
in one of three ways depending on what you hand it:

**A reactive table + a key** — the most common case. You get a ref
that reads and writes `source[key]` directly:

```lua
local makeReactive = reactive.reactive
local toRef = reactive.toRef

local state = makeReactive({ count = 0 })
local countRef = toRef(state, "count")

countRef.value = 5
print(state.count)   -- 5, they're the same underlying value
```

**A getter function** — a read-only ref that calls your function
fresh every time `.value` is read:

```lua
local ref = reactive.ref

local celsius = ref(20)
local fahrenheit = toRef(function()
  return celsius.value * 9 / 5 + 32
end)

print(fahrenheit.value)   -- 68
```

**Anything else** — behaves just like `ref()`.

One more nicety: pass a `defaultValue` as the third argument, and
`toRef()` will hand that back for a key that doesn't exist yet —
handy for optional fields you haven't set up front:

```lua
local settings = makeReactive({})
local theme = toRef(settings, "theme", "light")
print(theme.value)   -- "light", even though settings.theme is nil
```

## `toRefs()` — destructuring without losing reactivity

Here's a trap: if you pull fields out of a `reactive()` table into
local variables, you lose the connection — locals are just plain
values, not refs.

```lua
local state2 = makeReactive({ x = 1, y = 2 })
local x = state2.x   -- just a number, 1. Not linked to state2.x anymore.
```

`toRefs()` solves this by converting every field into its own linked
ref, all at once:

```lua
local toRefs = reactive.toRefs

local refs = toRefs(state2)

effect(function()
  print(refs.x.value, refs.y.value)
end)

state2.x = 99   -- triggers the effect above, since refs.x is linked
```

Worth knowing: `toRefs()` snapshots which *keys* exist at the moment
you call it. Adding a brand-new key to `state` afterward won't
retroactively show up in the `refs` table — but every ref it already
handed you keeps working correctly for as long as `state` exists.

## `proxyRefs()` — mixing refs and plain values

If you're writing something that returns a table mixing some
ref-valued fields with some plain ones (a common shape for a
"setup"-style function), `proxyRefs()` smooths it over: reads
auto-unwrap any refs, and writes forward into an existing ref's
`.value` instead of clobbering the ref itself.

```lua
local ref = reactive.ref
local proxyRefs = reactive.proxyRefs

local function useCounter()
  local count = ref(0)
  return proxyRefs({
    count = count,
    label = "a counter",   -- a plain value, mixed right in
  })
end

local counter = useCounter()
print(counter.count)   -- 0, not a ref object
counter.count = 5       -- forwards to count.value = 5 under the hood
```

## For Vue folks

> **For Vue folks:** `toRef()`'s getter-function form is intentionally
> simpler here than Vue's — it calls your function fresh on every
> read rather than wrapping it in an internal `computed()` for
> caching. In practice this rarely matters (reads inside an
> `effect()`/`watch()` still track correctly either way), but if your
> getter is expensive *and* read many times between actual dependency
> changes, know that there's no caching layer smoothing that out here.

## Reference

Full signatures and details: [`reference/ref.md`](reference/ref.md).
