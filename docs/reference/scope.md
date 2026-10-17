# `scope`

See [`effectScope()`](../08-effect-scope.md) for an introduction with
examples.

---

## `reactive.effectScope()`

```
reactive.effectScope() -> EffectScope
```

Creates a new scope, starting active.

## `scope:run(fn)`

```
scope:run(fn) -> any
```

Runs `fn()` with this scope active. Any `effect()`, `watch()`,
`watchEffect()`, or `computed()` created during `fn` is collected by
this scope.

Returns whatever `fn` returns. If the scope was already stopped,
`fn` is not called at all and this returns `nil`.

## `scope:stop()`

```
scope:stop() -> nil
```

Stops every effect/watcher this scope collected, then runs every
`onScopeDispose()` callback registered against it, in reverse
registration order (last in, first run). Marks the scope inactive.

**`computed()` is handled differently from the rest:** `effect()`
and `watch()`/`watchEffect()` are fully torn down and never usable
again. A collected `computed()` is only frozen — equivalent to
calling its own [`:stop()`](computed.md#computedstop) — so its last
value stays valid and readable forever for anything still depending
on it; it just never recomputes again.

Idempotent — calling `:stop()` again on an already-stopped scope does
nothing.

## `scope:pause()`

```
scope:pause() -> nil
```

Calls `:pause()` on every effect/watcher/computed this scope has
collected. A no-op if the scope is already stopped.

## `scope:resume()`

```
scope:resume() -> nil
```

Calls `:resume()` on every effect/watcher/computed this scope has
collected. A no-op if the scope is already stopped.

## `scope.active`

```
scope.active -> boolean
```

Plain boolean field. `true` until `:stop()` is called.

## `reactive.getCurrentScope()`

```
reactive.getCurrentScope() -> EffectScope | nil
```

Returns whichever scope is currently running (i.e. the innermost
active `scope:run(fn)` call), or `nil` if none is active.

## `reactive.onScopeDispose(fn, failSilently?)`

```
reactive.onScopeDispose(fn, failSilently?) -> nil
```

Registers `fn` to run when the currently active scope is stopped —
must be called from within a `scope:run(fn)` call.

- `failSilently` not set (or falsy): raises an error if there's no
  active scope.
- `failSilently = true`: silently does nothing instead.
