# `reactive`

See [`reactive()`](../04-reactive-objects.md) for an introduction to
`reactive`, `isReactive`, `isProxy`, `toRaw`, `markRaw`, and
`toReactive` with examples. See
[Reactive variants](../07-reactive-variants.md) for an introduction to
`shallowReactive`, `readonly`, and `shallowReadonly` (documented
further down in this same file) with examples.

---

## `reactive.reactive(target)`

```
reactive.reactive(target) -> table
```

Wraps `target` (a plain Lua table) in a reactive, deep, read/write
proxy. Reads and writes go through normal table syntax
(`proxy.key`, `proxy.key = value`) — no `.value` involved.

- If `target` isn't a table, it's returned unchanged.
- If `target` is already a proxy from any of the four reactive-family
  constructors (`reactive`, `shallowReactive`, `readonly`,
  `shallowReadonly`), it's returned unchanged.
- If `target` was marked with `markRaw()`, it's returned unchanged.
- Calling `reactive()` twice on the same raw table returns the exact
  same proxy both times — there's no risk of ending up with two
  different proxies over the same data.
- Nested table values are wrapped the same way (as `reactive()`),
  lazily — only when actually read, not upfront.
- A ref stored as a field's value auto-unwraps on read, and a write
  to that field forwards into the ref's `.value` instead of replacing
  the ref itself. See [`reactive()`](../04-reactive-objects.md#refs-inside-a-reactive-table).
- `pairs()`, `#`, and `ipairs()` all work and are reactive. See
  [Iteration details](../11-iteration-details.md) for exactly what
  triggers what.

## `reactive.shallowReactive(target)`

```
reactive.shallowReactive(target) -> table
```

Like `reactive()`, but only the top-level table's own keys are
tracked and lazily wrapped — a table value stored at a key is
returned exactly as-is, not wrapped in anything.

## `reactive.readonly(target)`

```
reactive.readonly(target) -> table
```

Wraps `target` in a deep, read-only proxy. Reading works normally;
writing anywhere — including into nested tables, which are themselves
wrapped as `readonly()` too — raises an error immediately.

Reading through a `readonly()` proxy does not track a dependency: a
readonly proxy can never itself be the source of a change, so there's
nothing meaningful to track.

## `reactive.shallowReadonly(target)`

```
reactive.shallowReadonly(target) -> table
```

Combines `readonly()` and `shallowReactive()`: top-level writes error,
but a table value stored at a key is left exactly as given — not
wrapped in `reactive()`, not wrapped in `readonly()`, fully mutable
and untracked.

## `reactive.isReactive(value)`

```
reactive.isReactive(value) -> boolean
```

True for a proxy produced by any of the four variant constructors
(`reactive`, `shallowReactive`, `readonly`, `shallowReadonly`). False
for a plain table, `nil`, or anything else.

**Note:** unlike Vue's own `isReactive()`, this does not exclude a
pure `readonly()` proxy — it's true for any of the four variants. Use
`isReadonly()` below if you need to know specifically whether
something is readonly.

## `reactive.isReadonly(value)`

```
reactive.isReadonly(value) -> boolean
```

True specifically for a `readonly()` or `shallowReadonly()` proxy.
False for a plain `reactive()`/`shallowReactive()` proxy, a plain
table, or anything else.

## `reactive.isShallow(value)`

```
reactive.isShallow(value) -> boolean
```

True specifically for a `shallowReactive()` or `shallowReadonly()`
proxy. False for a plain `reactive()`/`readonly()` proxy or anything
else.

This is `reactive.lua`'s own `isShallow()`, checking a reactive-family
proxy specifically. There's also a combined top-level
`reactive.isShallow()` (exposed from `init.lua`) that additionally
recognizes a `shallowRef()` — see
[`reference/ref.md`](ref.md#reactiveisshallowvalue) for that side of
it. The two checks look at structurally different shapes, so trying
one after the other is safe: nothing is ever both a ref and a
reactive-family proxy at once.

## `reactive.isProxy(value)`

```
reactive.isProxy(value) -> boolean
```

Same check as `isReactive()` — an alias, kept as a separate name to
match Vue's own API surface.

## `reactive.toRaw(value)`

```
reactive.toRaw(value) -> any
```

Returns the underlying raw table of a reactive-family proxy (any
variant). If `value` isn't a proxy, returns it unchanged — safe to
call on anything, proxy or not.

## `reactive.markRaw(value)`

```
reactive.markRaw(value) -> value
```

Marks `value` so none of the four reactive-family constructors ever
wrap it, even nested inside a `reactive()` structure. Returns `value`
itself, so it's safe to use inline:

```lua
local state = reactive.reactive({
  thing = reactive.markRaw(someTable),
})
```

Only affects tables — calling it on a non-table value is a harmless
no-op that just returns the value back.

## `reactive.toReactive(value)`

```
reactive.toReactive(value) -> any
```

`reactive(value)` if `value` is a table, otherwise `value` unchanged.
A small convenience mostly useful when writing your own code that
wants "wrap it if it's wrappable, leave it alone otherwise" without
an extra `type()` check at every call site.
