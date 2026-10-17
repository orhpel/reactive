# Deep watching

By default, `watch()` on a `reactive()` table's field only notices a
change to that exact field. What if you want to know about *anything*
changing anywhere inside a structure — a nested field three levels
down, a new key being added, all of it? That's what `deep` is for.

## The basics

Watch a `reactive()` table directly (not a getter pulling out one
field), and it's already deep by default — no options needed:

```lua
local reactive = require("reactive")
local makeReactive = reactive.reactive
local watch = reactive.watch

local state = makeReactive({
  user = { name = "Ada", address = { city = "London" } },
})

watch(state, function()
  print("something in state changed")
end)

state.user.address.city = "Paris"   -- triggers, even though it's nested
```

If your source is a getter function or a `ref` instead, you need to
opt in explicitly with `deep = true`:

```lua
local ref = reactive.ref

local box = ref({ value = { nested = 1 } })

watch(box, function()
  print("box changed")
end, { deep = true })

box.value.nested = 2   -- triggers, thanks to deep = true
```

Without `deep`, that same watcher would only notice `box.value` being
replaced wholesale — not a mutation two levels in.

## Limiting how deep you go: `deep = N`

Sometimes "watch absolutely everything, forever" is more than you
need — maybe you only care about one or two levels down, and want to
skip triggering on deeply nested churn you don't care about. `deep`
also accepts a number: how many levels below the root to descend
into.

```lua
local nested = makeReactive({ a = { b = { c = 1 } } })

watch(nested, function()
  print("changed")
end, { deep = 1 })

nested.a.b = { c = 99 }   -- triggers (this IS one level down)
nested.a.b.c = 100        -- does NOT trigger (that's two levels down)
```

Here's the full picture:

| `deep` | Reads root keys | Descends into level 1 | Descends into level 2 | Reacts to `state.a.b.c = x`? |
|---|---|---|---|---|
| `0` (or `false`) | yes | no | no | no |
| `1` | yes | yes | no | no (only `state.a.b = x` triggers) |
| `2` | yes | yes | yes | yes |
| `true` | yes | yes | yes, unlimited | yes |

Even `deep = 0` isn't "watch nothing" — it still reacts to the root
table's own fields changing, or a new key being added at the root. It
just never looks inside any of those fields' own values.

## The one gotcha: deep-watched values are always "the same object"

Here's something worth knowing before it surprises you: a
`reactive()` proxy is always the *exact same reference* every time
you read it — calling `reactive()` twice on the same data gives you
back the identical proxy. That means when you deep-watch a
`reactive()` value, `newValue` and `oldValue` in your callback end up
being **the same object**:

```lua
local identityCheck = makeReactive({ count = 0 })

watch(identityCheck, function(newValue, oldValue)
  print(newValue == oldValue)   -- true! same proxy, always
end, { deep = true })

identityCheck.count = 1
```

This isn't a bug — there's no meaningful "snapshot of how things
used to look" to hand you for a deeply-watched object, only "yes,
something in here changed, and here's the (still current) object."
If you need the actual old value of a specific field, watch that
field directly with a getter instead of deep-watching the whole
structure.

## Reference

Full details, including exactly how the depth counting works: see
`deep` in [`reference/watch.md`](reference/watch.md).
