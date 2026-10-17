# `reactive()`

`ref()` is great for a single value. But most real state is a bunch
of related fields living in a table — and wrapping every single one
in its own `ref()` gets old fast. `reactive()` fixes that: hand it a
table, get back a table that's reactive all the way through.

```lua
local reactive = require("reactive")
local makeReactive = reactive.reactive
local effect = reactive.effect

local user = makeReactive({
  name = "Ada",
  age = 30,
})

effect(function()
  print(user.name, "is", user.age)
end)
-- prints "Ada is 30"

user.age = 31
-- prints "Ada is 31", automatically
```

No `.value` anywhere — you read and write fields exactly like a
normal table, and it just works. Under the hood it's still the same
tracking machinery as `ref()`, applied per field instead of to one
single value.

## Nested tables just work

Got a table inside your table? Also reactive, no extra step needed:

```lua
local settings = makeReactive({
  display = {
    brightness = 80,
  },
})

effect(function()
  print("brightness:", settings.display.brightness)
end)

settings.display.brightness = 50   -- triggers the effect above, as expected
```

This wrapping happens lazily — the first time you actually *read* a
nested table, not upfront when you call `reactive()`. So wrapping a
huge structure with `reactive()` is cheap even if you only ever touch
a small corner of it.

## `pairs()` and `#` behave the way you'd hope

Loop over a reactive table, or take its length, and both are tracked
just like reading a specific field:

```lua
local list = makeReactive({ "a", "b", "c" })

effect(function()
  print("length is", #list)
end)

table.insert(list, "d")   -- triggers, prints "length is 4"
```

Same story for `ipairs()` — loop over a reactive array with it, and
an effect that does so re-runs correctly when values change,
elements get appended, or the array shrinks. (There's more nuance
here than you probably need right now — see
[Iteration details](11-iteration-details.md) if you're curious about
the fine print.)

## Escaping the proxy: `toRaw()`

Every `reactive()` call gives you back a *proxy* — the real data
lives underneath it. Almost all the time you don't need to care. But
sometimes you want the actual plain table — handing data off to code
that doesn't expect (or doesn't want) a reactive proxy, debugging,
serialization, that kind of thing. That's `toRaw()`:

```lua
local toRaw = reactive.toRaw

local raw = toRaw(user)
-- raw is a plain table, no tracking, no proxy
```

## Opting out entirely: `markRaw()`

Sometimes you have a table that should *never* become reactive — a
big third-party object, a class instance with its own internal state,
something where wrapping it would be pointless or actively unhelpful.
`markRaw()` says "hands off, forever":

```lua
local markRaw = reactive.markRaw

local thirdPartyThing = markRaw({ ... })

local state = makeReactive({
  thing = thirdPartyThing,
})

-- state.thing is the exact same table, never wrapped, even nested
-- inside a reactive() structure
```

## Refs inside a reactive table

If you stash a `ref` as a field's value, reading that field
auto-unwraps it — you get the ref's `.value` directly, not the ref
itself:

```lua
local ref = reactive.ref

local count = ref(0)
local state = makeReactive({ count = count })

print(state.count)   -- 0, not a ref object
state.count = 5      -- sets count.value = 5, the ref itself isn't replaced
print(count.value)   -- 5
```

Handy when you're assembling a table out of a mix of refs and plain
values and want everything to read the same way at the call site.

## Reference

Full signatures and details: [`reference/reactive.md`](reference/reactive.md).
