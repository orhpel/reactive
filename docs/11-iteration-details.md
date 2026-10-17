# Iteration details

`pairs()`, `ipairs()`, and `#` all work reactively on a `reactive()`
table, as mentioned back in [`reactive()`](04-reactive-objects.md).
This chapter is the fine print — what exactly triggers a re-run, and
one genuinely useful edge case involving `break`.

## `pairs()` and `#`

Both are tracked, and both react not just to values changing but to
keys being added or removed:

```lua
local reactive = require("reactive")
local makeReactive = reactive.reactive
local effect = reactive.effect

local state = makeReactive({ a = 1, b = 2 })

effect(function()
  local count = 0
  for _ in pairs(state) do count = count + 1 end
  print("key count:", count)
end)
-- prints "key count: 2"

state.c = 3
-- prints "key count: 3" -- pairs() noticed the new key
```

`#` behaves the same way — an effect reading the length re-runs when
whatever affects that length changes:

```lua
local list = makeReactive({ "a", "b", "c" })

effect(function()
  print("length:", #list)
end)

table.insert(list, "d")   -- triggers, "length: 4"
```

## `ipairs()` — reactive too, and here's the fun part why

`ipairs()` reacts correctly to value changes, appends, and
truncation, same as you'd expect:

```lua
local arr = makeReactive({ 10, 20, 30 })

effect(function()
  local sum = 0
  for _, v in ipairs(arr) do sum = sum + v end
  print("sum:", sum)
end)
-- prints "sum: 60"

arr[2] = 99
-- prints "sum: 139"

arr[4] = 40
-- prints "sum: 179" -- appending past the end is noticed too

arr[3] = nil
-- prints "sum: 139" -- and so is truncating
```

Here's the neat bit: `ipairs()` isn't specially instrumented at all.
It works purely as a side effect of how it's implemented — `ipairs()`
walks `t[1]`, `t[2]`, `t[3]`, ... until it hits `nil`, and every one
of those reads (including the very last one, the miss that stops the
loop) goes through the same tracked read as any other table access.
No dedicated logic was needed to make this work.

## The `break` edge case

Since only what actually gets *read* is tracked, a loop that exits
early via `break` never establishes a dependency on the indices it
never reached:

```lua
local arr2 = makeReactive({ 10, 20, 30 })
local runs = 0

effect(function()
  for i in ipairs(arr2) do
    if i == 1 then break end   -- stops after index 1
  end
  runs = runs + 1
end)

arr2[2] = 999   -- does NOT trigger -- index 2 was never actually read
print(runs)     -- still 1
```

This isn't a limitation to work around — it's the same "only what was
read gets tracked" rule that applies everywhere else in this library,
just showing up somewhere you might not have expected it. If you need
a loop to always establish a dependency on every element regardless
of an early exit, don't `break` out of it.

## Reference

`pairs`/`ipairs`/`#` aren't separate functions to document — they're
built-in Lua operations that work correctly against whatever
`reactive()` returns. See [`reference/reactive.md`](reference/reactive.md)
for `reactive()` itself.
