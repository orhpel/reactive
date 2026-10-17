# `ref`

See [`ref()` and `effect()`](../02-ref-and-effect.md) for an
introduction to `ref`, `isRef`, `unref`, `toValue`, and `triggerRef`
with examples. See [The `ref` family](../06-ref-variants.md) for an
introduction to `shallowRef`, `toRef`, `toRefs`, and `proxyRefs`
(documented further down in this same file) with examples.

---

## `reactive.ref(value)`

```
reactive.ref(value) -> ref
```

Wraps `value` in a ref. Access/change the value via `.value`.

- If `value` is already a ref (of any kind — `ref`, `shallowRef`,
  `computed`, or either shape `toRef()` returns), returns it
  unchanged.
- If `value` is a table, it's deep-wrapped via `reactive()` — mutating
  a nested field of `.value` is tracked/triggers just like mutating
  the ref itself. See [`reference/reactive.md`](reactive.md) for what
  "deep" means exactly.
- Reading `.value` inside an `effect()` or `watch()` tracks it.
  Writing a new value (compared by `toRaw()` on both sides, so a
  reactive proxy and its own underlying raw table count as equal)
  triggers subscribers if the value actually changed.

## `reactive.isRef(value)`

```
reactive.isRef(value) -> boolean
```

True for anything produced by `ref()`, `shallowRef()`, `computed()`,
or `toRef()` (either of its two return shapes). False for anything
else, including plain tables and `nil` — safe to call on anything.

## `reactive.unref(value)`

```
reactive.unref(value) -> any
```

Returns `value.value` if `value` is a ref, otherwise returns `value`
unchanged. Handy when a function accepts "a ref or a plain value" and
just wants the current value either way.

## `reactive.toValue(source)`

```
reactive.toValue(source) -> any
```

Like `unref()`, but also calls through a zero-argument getter
function:

```lua
local reactive = require("reactive")
local toValue = reactive.toValue

toValue(reactive.ref(5))         -- 5
toValue(5)                       -- 5
toValue(function() return 5 end) -- 5
```

## `reactive.triggerRef(ref)`

```
reactive.triggerRef(ref) -> nil
```

Force-notifies a ref's subscribers even if `.value` itself didn't
change by comparison. Useful after mutating a table stored inside a
**shallow** ref in place — since a shallow ref's stored table is never
wrapped, mutating into it produces no tracking/triggering on its own:

```lua
local shallowRef = reactive.shallowRef
local effect = reactive.effect
local triggerRef = reactive.triggerRef

local state = shallowRef({ count = 0 })

effect(function()
  print(state.value.count)
end)

state.value.count = 1   -- nothing happens, this write isn't tracked
triggerRef(state)       -- forces the effect above to re-run
```

For a normal (non-shallow) `ref()`, you won't usually need this —
nested mutations are already tracked because the table is deep-wrapped
automatically.

## `reactive.shallowRef(value)`

```
reactive.shallowRef(value) -> ref
```

Like `ref()`, but a table value is stored exactly as given — **not**
deep-wrapped via `reactive()`. Reassigning `.value` wholesale still
tracks/triggers normally (compared via `toRaw()` on both sides, same
as `ref()`). Mutating *into* the stored value in place is **not**
tracked — use `triggerRef()` to notify manually after doing so.

## `reactive.isShallow(value)`

```
reactive.isShallow(value) -> boolean
```

True only for a ref created by `shallowRef()` specifically — false
for a normal `ref()`, a `computed()`, either shape `toRef()` returns,
or any non-ref value.

(This is `ref.lua`'s own `isShallow()`. There's also a combined
top-level `reactive.isShallow()` that additionally recognizes
`shallowReactive()`/`shallowReadonly()` proxies — see
[`reference/reactive.md`](reactive.md#reactiveisshallowvalue) — the
one described here is what that combined version delegates to for the
ref case.)

## `reactive.toRef(source, key?, defaultValue?)`

```
reactive.toRef(source, key?, defaultValue?) -> ref
```

Returns a ref, with the exact behavior depending on what's passed —
checked in this order:

1. **`source` is already a ref** (any kind) — returned unchanged.
2. **`source` is a function** — wrapped in a read-only ref whose
   `.value` calls the function fresh on every read. Writing `.value`
   errors, same as a getter-only `computed()`. (See the "For Vue
   folks" note in [The `ref` family](../06-ref-variants.md) — this
   doesn't cache internally the way Vue's own getter-ref does.)
3. **`source` is a table and `key` is given** — a ref with no value
   of its own: reading/writing `.value` reads/writes `source[key]`
   directly. If `source` is a `reactive()` proxy, tracking/triggering
   comes entirely from `source`'s own reactivity — this ref adds none
   of its own. If `source[key]` is currently `nil`, `.value` returns
   `defaultValue` instead.
4. **Anything else** — same as `reactive.ref(source)`.

If the value already at `source[key]` (case 3) is itself a ref,
`toRef()` returns that existing ref as-is rather than wrapping it in
another layer.

## `reactive.toRefs(source)`

```
reactive.toRefs(source) -> table
```

Converts a `reactive()` table into a plain Lua table of refs, one per
key present **at call time** — built by calling `toRef(source, key)`
for each. Not itself reactive to keys added to `source` later (the
key set is a one-time snapshot), but every ref it returns stays
correctly linked to its own key going forward.

## `reactive.proxyRefs(objectWithRefs)`

```
reactive.proxyRefs(objectWithRefs) -> table
```

Wraps a plain table so that reads auto-unwrap any ref-valued fields,
and writes to a field currently holding a ref forward into that ref's
`.value` instead of replacing the ref itself. Fields holding plain
(non-ref) values pass through untouched in both directions.

If `objectWithRefs` is already a `reactive()` proxy, this is a no-op
that returns it unchanged — a `reactive()` proxy already auto-unwraps
refs on its own.
