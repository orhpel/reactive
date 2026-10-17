# `computed`

See [`computed()`](../03-computed.md) for an introduction with
examples.

---

## `reactive.computed(getterOrOptions)`

```
reactive.computed(getterOrOptions) -> ref
```

Creates a lazily-evaluated, cached computed ref.

`getterOrOptions` is either:

- **A function** `function(oldValue) -> newValue` — a read-only
  computed. Writing to `.value` raises an error.
- **A table** `{ get = function() -> newValue, set = function(newValue) }`
  — a writable computed. Reading `.value` calls `get`; writing calls
  `set` with the new value (whatever `set` does with it — typically
  updating the underlying refs it's derived from).

Returns a ref-shaped value (`reactive.isRef()` is true for it). Read
it the same way as any other ref, via `.value`.

**Laziness and caching:** the getter runs on the first read of
`.value`, and its result is cached. It only re-runs the next time
`.value` is read *after* at least one of its dependencies has
actually changed — reading `.value` repeatedly with nothing changed
in between reuses the cached result and does not re-invoke the
getter.

**Dependency tracking:** works exactly like inside an `effect()` —
whatever refs/reactive properties the getter reads during its run
become its tracked dependencies, re-discovered fresh on every actual
recomputation. A computed can depend on other computeds; changes
propagate through the whole chain correctly.

**Note:** the getter receives the previous cached value as its
argument (`oldValue`) — most getters ignore it, but it's there if you
need to compare against or build on the last computed result.

If created while a `scope:run(fn)` is active, the computed is
automatically collected by that scope — see
[`effectScope()`](../08-effect-scope.md#computed-is-collected-too--with-one-twist)
for what that means for `scope:stop()` specifically.

## `computed:stop()`

```
computed:stop() -> nil
```

Permanently detaches this computed from its own dependencies. After
this, `.value` never recomputes again, regardless of what its
former dependencies do — it keeps returning whatever it last
computed, forever.

Only the computed's *incoming* edges (what it reads) are cut. Its
*outgoing* edge — the fact that other effects/watchers/computeds may
depend on reading `.value` from it — is left completely untouched;
anything already depending on it keeps reading a valid, unchanging
value with no error and no special handling required on their part.

Idempotent — calling `:stop()` again on an already-stopped computed
is a no-op.

## `computed:pause()`

```
computed:pause() -> nil
```

Temporarily suspends recomputation. `.value` keeps returning the
last computed value even if a dependency changes while paused.
Unlike `:stop()`, dependency links are left fully intact.

## `computed:resume()`

```
computed:resume() -> nil
```

Reverses `:pause()`. No explicit "catch-up" step is needed or
performed — the next `.value` read after `:resume()` simply
recomputes normally if anything changed while paused, exactly as it
would have without the pause.
