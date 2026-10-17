# Lua stdlib interop

Good news up front: Lua's `table` library already plays nicely with
`reactive()` proxies. You don't need any special wrapper functions —
`table.insert`, `table.remove`, `table.sort`, and friends all just
work, reactively, exactly like you'd hope.

```lua
local reactive = require("reactive")
local makeReactive = reactive.reactive
local effect = reactive.effect

local list = makeReactive({ 3, 1, 2 })

effect(function()
  print("list is now:", table.concat(list, ", "))
end)
-- prints "list is now: 3, 1, 2"

table.sort(list)
-- prints "list is now: 1, 2, 3"
```

This works because Lua's `table.*` functions respect a table's
metamethods when reading and writing — which is exactly the mechanism
`reactive()` proxies are built on. No special-casing needed on our
end.

Specifically verified to work correctly and reactively:
`table.insert`, `table.remove`, `table.sort` (with or without a
custom comparator), `table.concat` (a pure read, triggers nothing —
as expected), `table.unpack`, and `table.move` (correctly moving
between two *different* reactive tables).

## Watch out for re-run storms

Here's the one thing worth actually knowing: a function like
`table.sort()` does a lot of small writes internally (every swap
during the sort). Each one is individually tracked and individually
triggers — which is *correct*, but can mean way more effect re-runs
than you actually wanted for what is, conceptually, one operation.

Sorting a modestly-sized reverse-ordered array can genuinely trigger
a couple hundred re-runs if nothing coalesces them.

The fix is the same one that already applies to any block of several
writes: wrap it in a batch.

```lua
local batchEffect = reactive.internal.effect

batchEffect.startBatch()
table.sort(myReactiveArray)
batchEffect.endBatch()
```

Everything inside the batch still writes and triggers exactly as
before — but dependent effects only actually re-run once, after
`endBatch()`, not once per intermediate write. This isn't specific to
`table.sort()` either — the same trick helps any time you're about to
do a bunch of individual writes to a reactive table and only care
about the *end result* triggering a re-run, not each step along the
way.

## The one thing to never do: `rawset()` / `rawget()`

This one's not a "gotcha," it's closer to a landmine — please actually
avoid it.

```lua
-- DON'T DO THIS:
rawset(myReactiveProxy, "key", "value")
```

`rawset()`/`rawget()` exist specifically to bypass metamethods
entirely — that's their whole purpose. On a `reactive()` proxy, that
means the write goes straight onto the (normally empty) proxy table
itself, completely skipping the tracking/triggering logic. This isn't
just "untracked" — it's actively worse: from that point on,
`proxy.key` and the real underlying data silently disagree with each
other, because reads now find the value sitting directly on the proxy
before they ever get to the real data underneath.

There's no way to guard against this from inside the library —
`rawset`/`rawget` skip metamethods by design, so there's no hook to
intercept them with. The only fix is: don't call them on a
`reactive()`-family proxy. Ever. If you genuinely need raw,
un-tracked access to the underlying table, use `toRaw()` first and
operate on *that* instead.

## What about `string.*`, `os.*`, `io.*`?

Not a concern. None of them mutate arbitrary Lua tables the way
`table.*` does — `string.*` works on strings, `os.time()` only ever
*reads* an optional table argument, and `io.*` doesn't deal in Lua
tables as its primary data structure at all. Nothing to watch out for
there.

## Reference

There's no dedicated reference file for stdlib interop — this
behavior isn't something `reactive.lua` implements, it's a property
of how Lua's own `table.*` functions already work against any table
with metamethods. `startBatch()`/`endBatch()` are available via
`reactive.internal.effect` for the batching pattern above.
