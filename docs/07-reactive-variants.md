# Reactive variants

`reactive()` is deep and read-write — the sensible default for most
state. But sometimes you want something narrower: only the top level
tracked, or nothing writable at all. Three more constructors cover
those cases.

## `shallowReactive()` — top level only

Same idea as `shallowRef()`, applied to a whole table: the table's
own keys are tracked, but a table stored *inside* it is left
completely alone — not wrapped, not tracked.

```lua
local reactive = require("reactive")
local shallowReactive = reactive.shallowReactive
local effect = reactive.effect

local state = shallowReactive({
  count = 0,
  nested = { value = 1 },
})

effect(function()
  print(state.count, state.nested.value)
end)

state.count = 1              -- triggers, top level is tracked
state.nested.value = 99      -- does NOT trigger, nested is untouched
```

Reach for this when you're deliberately managing a nested structure
yourself and don't want (or need) the overhead of wrapping it too.

## `readonly()` — guard against accidental writes

`readonly()` gives you a deep, read-only view of a table. Reading
works exactly like a normal table; writing — anywhere, including
nested — raises an error immediately.

```lua
local makeReactive = reactive.reactive
local readonly = reactive.readonly

local original = makeReactive({ count = 0 })
local view = readonly(original)

print(view.count)   -- 0, reading is fine

view.count = 5       -- error! writes are rejected, loudly
```

This is handy for handing data to code that should only ever *look*,
never touch — think exposing internal state to a UI layer that
displays it but has no business mutating it directly.

Since a `readonly()` proxy can never itself be the source of a
change (nothing can write through it), reading from one inside an
`effect()` doesn't establish a dependency — there's nothing for it to
ever notify you about. If the *underlying* data changes through some
other route (say, the original `reactive()` proxy it was built from),
that's tracked through that other reference, not through the
readonly view.

## `shallowReadonly()` — the combination

Exactly what it sounds like: top-level writes are rejected, but
nested tables are left fully mutable and untouched — not wrapped in
`readonly()`, not wrapped in anything.

```lua
local shallowReadonly = reactive.shallowReadonly

local props = shallowReadonly({
  label = "Submit",
  style = { color = "blue" },
})

props.label = "Cancel"        -- error, top level is readonly
props.style.color = "red"     -- works fine, nested is untouched
```

A good fit for something like a "props" object: the caller shouldn't
be able to swap out which values were passed in, but you don't want
to pay for (or force) deep readonly-wrapping of whatever's nested
inside them.

## Checking what you've got

`isReadonly()` tells you if something is a `readonly()` or
`shallowReadonly()` proxy specifically. The combined `isShallow()`
(covered in [`reference/reactive.md`](reference/reactive.md)) tells
you if something is either shallow variant — or a `shallowRef()`, for
that matter, since it checks both families at once.

## For Vue folks

> **For Vue folks:** composing variants together doesn't work the way
> you might expect. In Vue, `readonly(reactive(x))` gives you a real
> readonly wrapper around the reactive proxy, while `reactive(readonly(x))`
> just returns the readonly proxy unchanged. Here, both directions
> collapse to the same simpler rule: calling any of the four
> constructors on something that's *already* some reactive-family
> proxy just returns that existing proxy, whichever variant you asked
> for. So `readonly(reactive(x))` here returns the plain `reactive()`
> proxy, not a genuine readonly wrapper around it — a real behavioral
> difference if you're relying on that specific Vue pattern.
>
> Also worth flagging: this library's `isReactive()` doesn't make
> Vue's own readonly-excluding distinction — it's simply true for any
> of the four variants. Use `isReadonly()` if you specifically need
> to know "is this readonly."

## Reference

Full signatures and details: [`reference/reactive.md`](reference/reactive.md).
