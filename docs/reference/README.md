# Reference

The prose docs (see [the guide](https://orhpel.github.io/reactive/)) explain what things are
*for* and how to use them, with examples. This reference is the terse,
precise version: every public function, its exact signature, and its
exact behavior — including the edge cases. If you already know roughly
what you want and just need to check a detail, you're in the right
place.

## Files

Grouped by topic, not by source file — so if you're looking for
`computed()`, you'll find it in `computed.md`, not buried inside
`ref.md` just because that's where it happens to live internally.

| File | Covers |
|---|---|
| [`ref`](ref.md) | `ref`, `shallowRef`, `isRef`, `isShallow`, `unref`, `toValue`, `triggerRef`, `toRef`, `toRefs`, `proxyRefs` |
| [`computed`](computed.md) | `computed` |
| [`reactive`](reactive.md) | `reactive`, `shallowReactive`, `readonly`, `shallowReadonly`, `isReactive`, `isReadonly`, `isShallow`, `isProxy`, `toRaw`, `markRaw`, `toReactive` |
| [`effect`](effect.md) | `effect`, `stop`, `onEffectCleanup`, `pauseTracking`, `enableTracking`, `resetTracking` |
| [`watch`](watch.md) | `watch`, `watchEffect`, `onWatcherCleanup` |
| [`scope`](scope.md) | `effectScope`, `getCurrentScope`, `onScopeDispose` |

Not covered here: `Dep`/`Link`, the free `track()`/`trigger()`
functions, and other internals. Those exist, but they're building
blocks for the library itself, not something you're meant to reach
for day to day.

## Reading a signature

```
reactive.toRef(source, key?, defaultValue?) -> ref
```

- A `?` after a parameter name means it's optional.
- Return types are named loosely (`ref`, `table`, `boolean`, ...) —
  this is Lua, not TypeScript, so treat these as descriptions, not
  strict contracts.
- `self`/`:` method calls (e.g. `scope:stop()`) are written with a
  colon, matching how you'd actually call them.

## "Deep" vs. "shallow"

You'll see these words a lot, so here's what they mean, once:

- **Deep** means nested tables are wrapped too, all the way down —
  and this happens lazily, only when you actually access a nested
  table, not eagerly for the whole structure up front.
- **Shallow** means only the top level is touched — a table value
  stored inside stays a plain, untracked, unwrapped table.

`reactive()` and `readonly()` are deep. `shallowReactive()` and
`shallowReadonly()` are shallow. `ref()` is deep for table values it
holds; `shallowRef()` is not.

## `internal` access

`reactive.internal` exposes the lower-level pieces (`Dep`, `Link`,
`ReactiveEffect`, the free `track()`/`trigger()` functions, and so
on) for advanced use — building a new kind of reactive primitive,
writing tests against internals, that sort of thing. Everyday code
should never need it; if you find yourself reaching for
`reactive.internal` to do something ordinary, there's very likely a
public function that already does it.
