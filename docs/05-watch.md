# `watch()` and `watchEffect()`

`effect()` re-runs a whole function whenever anything it reads
changes. Sometimes that's exactly what you want. Other times you want
something narrower: "tell me when *this specific thing* changes, and
give me the old and new value while you're at it." That's `watch()`.

## `watchEffect()` — the simple case

If you just want "run this again whenever its dependencies change,"
`watchEffect()` is `effect()` with a friendlier name and a cleanup
hook built in. It figures out its own dependencies automatically,
same as `effect()` does:

```lua
local reactive = require("reactive")
local makeReactive = reactive.reactive
local watchEffect = reactive.watchEffect

local user = makeReactive({ name = "Ada" })

watchEffect(function()
  print("hello,", user.name)
end)
-- prints "hello, Ada" right away

user.name = "Grace"
-- prints "hello, Grace"
```

## `watch()` — when you need old and new values

`watch()` is more deliberate: you give it an explicit source to
watch, and it hands your callback both the new and the previous
value:

```lua
local ref = reactive.ref
local watch = reactive.watch

local count = ref(0)

watch(count, function(newValue, oldValue)
  print("count went from", oldValue, "to", newValue)
end)

count.value = 5   -- prints "count went from 0 to 5"
```

A source can be a ref, a computed, or a getter function (handy for
watching a single field off a `reactive()` table without pulling in
the whole thing):

```lua
local settings = makeReactive({ volume = 50 })

watch(
  function() return settings.volume end,
  function(newValue, oldValue)
    print("volume:", oldValue, "->", newValue)
  end
)
```

## Options: `immediate` and `once`

```lua
watch(count, function(newValue, oldValue)
  print(newValue, oldValue)
end, { immediate = true })
-- runs right away too, with oldValue = nil the first time
```

`once = true` stops the watcher automatically after its first
callback run — useful for "wait for this one specific change and
then I'm done":

```lua
watch(count, function(newValue)
  print("count finally changed to", newValue)
end, { once = true })
```

## Cleaning up between runs

The callback (or `watchEffect`'s function) gets a third argument —
`onCleanup` — for registering something to run right before the
*next* trigger, or when the watcher stops. Classic use case: canceling
an in-flight request or timer that's about to be superseded.

```lua
watch(searchTerm, function(newValue, oldValue, onCleanup)
  local timerId = startDebounceTimer(newValue)
  onCleanup(function()
    cancelTimer(timerId)
  end)
end)
```

## Stopping, pausing, resuming

Both `watch()` and `watchEffect()` return a handle. Call it directly
to stop, or use its methods for finer control:

```lua
local handle = watchEffect(function()
  print(count.value)
end)

handle:pause()    -- stops reacting, but remembers it's "just paused"
handle:resume()   -- catches up on anything it missed while paused
handle()          -- stops for good (same as handle:stop())
```

## What's next

This covers the everyday shape of `watch()`. There's a `deep` option
for watching whole nested structures at once, which deserves its own
chapter — see [Deep watching](09-deep-watching.md) once you've got the
basics down.

## Reference

Full signatures and details: [`reference/watch.md`](reference/watch.md).
