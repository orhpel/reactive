# 02 — A Shopping Cart, or "Why Derived State Needs a Better Story"

**Shows off:** `reactive()`, computed chains, **writable** computed  
**Difficulty:** ⭐⭐  
**Why you'd use this:** You have state with multiple derived views, and
recomputing them all by hand is a bug factory.

## The premise

A cart has items. Each item has a price and a quantity. The cart has:

- a subtotal (sum of `price * quantity`)
- a tax amount (subtotal × tax rate)
- a total (subtotal + tax)
- a discount (0 by default; user can set it)
- the final charge (total − discount, floored at 0)

You want all of those to stay consistent. You want *none* of them to be
recomputable-by-hand.

## The naive version (don't do this)

```lua
-- This is the "we'll just remember to call recalc()" version.
local cart = { items = {}, tax_rate = 0.2, discount = 0 }

function cart:recalc()
  local subtotal = 0
  for _, item in ipairs(self.items) do
    subtotal = subtotal + item.price * item.quantity
  end
  self.subtotal = subtotal
  self.tax      = subtotal * self.tax_rate
  self.total    = subtotal + self.tax
  self.charge   = math.max(self.total - self.discount, 0)
end

cart:recalc()  -- remember to call this
cart:recalc()  -- did we call it? did anyone call it?
```

Every mutation site has to remember `cart:recalc()`. Every read site has
to trust that someone else already did. That's not a data model, that's
a prayer.

## With `reactive.lua`

```lua
local reactive = require("reactive")
local _reactive = reactive.reactive
local computed  = reactive.computed
local effect    = reactive.effect

-- The raw state. Deeply reactive: nested items, nested prices, all of it.
local cart = _reactive({
  items    = {},         -- { { name = "...", price = 0, quantity = 0 } }
  tax_rate = 0.2,
  discount = 0,          -- manually-set value, not derived
})

-- Derived: subtotal. Recomputes only when items or any item field changes.
local subtotal = computed(function()
  local sum = 0
  for _, item in ipairs(cart.items) do
    sum = sum + item.price * item.quantity
  end
  return sum
end)

-- Derived: tax.
local tax = computed(function()
  return subtotal.value * cart.tax_rate
end)

-- Derived: total.
local total = computed(function()
  return subtotal.value + tax.value
end)

-- Derived: final charge, floored at 0.
local charge = computed(function()
  return math.max(total.value - cart.discount, 0)
end)

-- Writable computed: `.value = x` writes to `cart.discount` and re-runs
-- the whole derived chain.
local discount = computed({
  get = function() return cart.discount end,
  set = function(v) cart.discount = math.max(v, 0) end,
})

-- A consumer: whenever the charge changes, log it.
effect(function()
  print(("cart total: %.2f  charge: %.2f"):format(total.value, charge.value))
end)
```

Now the fun part:

```lua
table.insert(cart.items, { name = "book", price = 25, quantity = 2 })
-- → effect prints "cart total: 60.00  charge: 60.00"
--   (subtotal=50, tax=10, total=60, charge=60)

cart.items[1].quantity = 3
-- → effect prints "cart total: 90.00  charge: 90.00"
--   (subtotal=75, tax=15, total=90)

discount.value = 20
-- → effect prints "cart total: 90.00  charge: 70.00"
```

Notice what we **didn't** do:

- We didn't manually invalidate `subtotal`, `tax`, `total`, or `charge`.
- We didn't re-walk the `items` array in `charge`.
- We didn't add a special case for `discount` in any of the derived
  computeds.

The dependency graph is:

```
cart.items[*].price ──┐
cart.items[*].quantity ─┴─> subtotal ─┐
                     cart.tax_rate ───┴─> tax ─┐
                                                ├─> total ─┐
                                    cart.discount ──────────┴─> charge ─> effect
```

Each arrow re-establishes itself **fresh on every run**, based on what
was actually read. If you add an "if item is on sale, price is 10%
off" branch to `subtotal`, the dependency tracking picks up the new
read (whatever field held the "on sale" flag) with zero extra work.

## The writable-computed trick

`discount` is a **writable computed** — a bidirectional bridge. Reading
`.value` reads `cart.discount`; writing `.value = x` writes
`cart.discount` (through the setter, which clamps negatives). This is
handy when:

- You want to expose a property to outside code as "just a ref", but it's
  really backed by a field on a bigger object.
- You want validation logic (clamping, coercion) to live at a single
  choke point.
- You want to change the *representation* later (e.g. move discount to
  a separate table) without touching every consumer.

## Why this scales

The classic "just recompute everything" approach works up to about 200
items and 5 derived fields. Then someone adds shipping cost (another
chain), tax rules per region (branching), and a coupon system that reads
from six places — and suddenly you're recomputing the universe on every
cart mutation.

`reactive.lua` caches each computed independently. Setting `cart.discount`
does **not** invalidate `subtotal` (which doesn't read discount). It only
invalidates `charge`. That's the whole point.

## Reference

- [`reactive()`](../04-reactive-objects.md) — deep proxy for plain Lua tables
- [`computed()`](../03-computed.md) — lazy, cached derived values; the same doc covers the writable form (`{ get, set }` table instead of a bare function)

→ **Next:** [03-config-auto-reload.md](03-config-auto-reload.md)