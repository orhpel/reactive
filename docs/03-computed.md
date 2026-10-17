# `computed()`

You've got a `ref`, and you need another value that's always "that,
but derived somehow" — a total, a formatted string, a filtered list.
You *could* keep it in sync by hand with an `effect()`. Please don't.
That's exactly what `computed()` is for.

```lua
local reactive = require("reactive")
local ref = reactive.ref
local computed = reactive.computed

local price = ref(10)
local quantity = ref(3)

local total = computed(function()
  return price.value * quantity.value
end)

print(total.value)   -- 30
quantity.value = 5
print(total.value)   -- 50, automatically
```

`total` behaves just like a ref — read it via `.value`, use it inside
an `effect()` or `watch()`, whatever you'd do with a normal ref. The
only difference is you never set it directly; its value is *derived*.

## Lazy and cached — the two things that make it worth using

`computed()` doesn't recalculate on every read, and it doesn't
recalculate the instant a dependency changes either. It's smarter than
that:

- **Lazy:** the getter function only runs when you actually read
  `.value`. Never read it? Never runs.
- **Cached:** once computed, the result is reused for every
  subsequent read — until one of its dependencies actually changes.
  Read `total.value` a hundred times in a row with nothing changing
  in between, and the getter runs exactly once.

```lua
local calls = 0
local expensive = computed(function()
  calls = calls + 1
  return price.value * quantity.value
end)

expensive.value
expensive.value
expensive.value
print(calls)   -- 1, not 3
```

This is the whole reason to reach for `computed()` instead of just
recalculating inline everywhere: you get the "always up to date"
guarantee of a live calculation with the performance of a cached one.

## Chaining computeds

A `computed()` can depend on another `computed()`, no special
handling needed — changes propagate all the way through:

```lua
local double = computed(function() return price.value * 2 end)
local quadruple = computed(function() return double.value * 2 end)

price.value = 5
print(quadruple.value)   -- 20
```

## Writable computeds

By default, writing to `.value` on a computed is an error — makes
sense, since Lua has no way to know what you'd *want* that to mean.
But if you give it both a getter and a setter, you get a computed you
can assign to as well:

```lua
local firstName = ref("Ada")
local lastName = ref("Lovelace")

local fullName = computed({
  get = function()
    return firstName.value .. " " .. lastName.value
  end,
  set = function(newValue)
    local first, last = newValue:match("^(%S+)%s+(%S+)$")
    firstName.value = first
    lastName.value = last
  end,
})

print(fullName.value)          -- "Ada Lovelace"
fullName.value = "Grace Hopper"
print(firstName.value)         -- "Grace"
```

## Stopping and pausing a computed

Sometimes you're done with a computed — or want it to just... hold
still for a while — without tearing down whatever depends on it.
`computed()` gives you two different tools for that, and they mean
genuinely different things.

### `:stop()` — permanently freeze the value

`:stop()` cuts a computed off from its own dependencies for good.
After this, `.value` never recalculates again — no matter what
`price` or `quantity` do from here on, `total.value` just keeps
returning whatever it last computed:

```lua
total:stop()

price.value = 999   -- total no longer cares
print(total.value)  -- still whatever it was before :stop()
```

Here's the part that's easy to miss: `:stop()` only cuts the
computed's *incoming* connections — what it reads. Anything that
depends *on* `total` (an `effect()`, another `computed()`, whatever)
keeps working exactly as before, still reading a perfectly valid
value. `:stop()` doesn't make `total` unusable, it just freezes it in
place. Calling `:stop()` twice is harmless — the second call is a
no-op.

### `:pause()` / `:resume()` — a temporary version

If you want that freeze to be temporary, use `:pause()` instead:

```lua
total:pause()

quantity.value = 10   -- total doesn't recompute yet
print(total.value)    -- still the old value

total:resume()
print(total.value)    -- now recomputes and reflects the change
```

Unlike `:stop()`, `:pause()` doesn't touch any dependency links at
all — it's purely "don't recalculate for now." The very next read
after `:resume()` picks up automatically on anything that changed in
the meantime. No manual "catch up" step needed.

### When you'd actually reach for these

Most of the time, you won't — a `computed()` that's just quietly
sitting there costs very little, and letting Lua's garbage collector
clean it up when nothing references it anymore is usually enough.
`:stop()`/`:pause()` earn their keep when a computed is *shared* —
say, exposed as part of a returned object — and something else might
still be holding a reference to it after you're done actively using
it, so simply "letting go" isn't an option.

The more common way you'll actually touch this, though, is indirectly
— see [`effectScope()`](08-effect-scope.md#computed-is-collected-too--with-one-twist),
which automatically includes any `computed()` created inside it.

## Reference

Full signature and details: [`reference/computed.md`](reference/computed.md).
