# `ref()` and `effect()`

These two are the whole foundation. Everything else in this library —
`computed()`, `reactive()`, `watch()` — is built on top of them (or is
just a friendlier wrapper around the same idea). Get comfortable with
these two, and the rest will feel obvious.

## `ref()` — a value that knows when it changes

A `ref` is a small box around a value. You read and write the value
through `.value`:

```lua
local reactive = require("reactive")
local ref = reactive.ref

local count = ref(0)
print(count.value)   -- 0
count.value = 5
print(count.value)   -- 5
```

On its own, that's not very exciting — it's a fancier variable. The
interesting part happens when something is *watching*.

## `effect()` — code that re-runs itself

`effect()` runs a function immediately, and then **automatically
re-runs it** whenever any ref (or reactive value) it read the first
time around changes:

```lua
local effect = reactive.effect

effect(function()
  print("count is", count.value)
end)
-- prints "count is 0" right away

count.value = 5
-- prints "count is 5", with zero extra code from you
```

That's the whole trick. The effect doesn't get told "hey, `count`
changed" — it just re-runs, reads `count.value` again, and naturally
picks up the new value. Behind the scenes, `reactive.lua` noticed
`count.value` was read *while the effect was running* and quietly
made a note: "this effect cares about this ref." Change the ref, and
every effect that made that note gets re-run.

This means the dependency list isn't something you declare up front —
it's discovered automatically, every run, just by looking at what got
read. Read a different ref next time (behind an `if`, say) and the
effect's dependencies update to match.

```lua
local useCount = ref(true)
local a = ref(1)
local b = ref(2)

effect(function()
  if useCount.value then
    print("a is", a.value)
  else
    print("b is", b.value)
  end
end)

b.value = 99      -- nothing happens, the effect never read b
useCount.value = false  -- effect re-runs, now reading b -- prints "b is 99"
b.value = 100     -- NOW this triggers a re-run, prints "b is 100"
```

## Stopping an effect

`effect()` returns a **runner**. Calling `runner()` re-runs the effect
manually; `runner.effect:stop()` stops it from ever re-running again:

```lua
local runner = effect(function()
  print("count is", count.value)
end)

runner.effect:stop()
count.value = 42   -- nothing prints, the effect is dead
```

## Cleaning up after yourself

If your effect sets something up that needs tearing down before the
next run (a timer, a subscription, whatever), register a cleanup with
`onEffectCleanup()`. It runs right before the effect's next run, and
also when the effect is stopped:

```lua
local onEffectCleanup = reactive.onEffectCleanup

effect(function()
  local id = startSomeTimer(count.value)
  onEffectCleanup(function()
    stopSomeTimer(id)
  end)
end)
```

## What about `computed()`?

If you're about to reach for `ref()` + `effect()` to derive one value
from another — say, `total.value = price.value * quantity.value` kept
in sync by hand — stop, that's exactly what
[`computed()`](03-computed.md) is for. Keep reading.

## Reference

Full signatures and edge cases: [`reference/ref.md`](reference/ref.md),
[`reference/effect.md`](reference/effect.md).
