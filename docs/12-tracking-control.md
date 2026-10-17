# Tracking control

Most of the time, you'll never need this chapter. `effect()`/`watch()`
automatically track exactly what they read, and that's almost always
exactly what you want. But every now and then, you want to read a
reactive value *without* it becoming a dependency — this is how.

## Why you'd want this

Say you're inside an effect and you need to read something purely for
a side purpose — logging, a debug check, a one-off decision — and you
specifically **don't** want that read to make the effect depend on it:

```lua
local reactive = require("reactive")
local ref = reactive.ref
local effect = reactive.effect
local pauseTracking = reactive.pauseTracking
local resetTracking = reactive.resetTracking

local count = ref(0)
local debugFlag = ref(false)

effect(function()
  pauseTracking()
  if debugFlag.value then
    print("debug: count is", count.value)
  end
  resetTracking()

  print("count is", count.value)   -- this read IS tracked, as normal
end)
```

In that example, changing `debugFlag` won't re-run the effect —
reading it happened while tracking was paused. Changing `count`
still will, since that read happened outside the paused block.

## The rules

- `pauseTracking()` and `enableTracking()` must always be matched with
  a later `resetTracking()` — they push onto a small internal stack,
  and `resetTracking()` pops it back to whatever state was active
  before. Forgetting to call `resetTracking()` leaves tracking in the
  wrong state for whatever runs afterward, so treat them as a pair,
  always.
- `enableTracking()` is the mirror case: force tracking back *on*
  inside a block where it would otherwise be off (nesting works
  correctly either way, thanks to the stack).

Honestly, most code will go its entire lifetime without needing
either of these. If you're not sure whether you need this, you
probably don't.

## Reference

Full signatures: [`reference/effect.md`](reference/effect.md).
