# Where we differ from Vue

If you've never touched Vue, feel free to skip this chapter entirely
— nothing here is required knowledge. If you have, here's the full,
honest list of where `reactive.lua` intentionally parts ways with
`@vue/reactivity`, and why. None of this is a bug or an oversight —
every item here was a deliberate call, usually because Lua (or this
project's actual needs) simply didn't call for the extra complexity.

## Dropped entirely

- **`Map`/`Set`/`WeakMap`/`WeakSet` reactivity.** Lua has exactly one
  table type, used as both object and array — there's no separate
  collection type to give special treatment to. A plain Lua table is
  "the" reactive container, full stop.
- **`Symbol`-keyed internal flags, `ownKeys`/`deleteProperty`/`has`
  traps.** These exist in Vue to make `Object.keys()`, `in`, and
  `delete obj.x` behave transparently through a JS `Proxy`. Lua's
  metatables don't have a direct equivalent for the last two — reads,
  writes, iteration, and length are all covered, but there's no hook
  for "someone deleted a key" or "someone checked membership"
  specifically.
- **Dev-only warnings.** Vue often logs a console warning instead of
  throwing (e.g. writing to a readonly proxy). This library prefers a
  hard Lua `error()` instead — a silently-ignored write is a much
  worse debugging experience than a loud failure right at the call
  site that caused it.
- **SSR-related branches.** Not applicable — there's no server-side
  rendering concept here.
- **TypeScript type-inference machinery** (`UnwrapRef` and friends).
  Compile-time-only constructs with zero runtime behavior — nothing
  to port.

## Simplified

- **`watch()`/`watchEffect()` have no scheduler.** Vue's `watch.ts`
  coordinates watcher callbacks with a component's render cycle. This
  library has no render cycle underneath it, so callbacks just run
  synchronously (still subject to the same batching that everything
  else uses).
- **No multi-source `watch()`** — `watch({a, b}, cb)` isn't supported.
  Call `watch()` once per source instead.
- **`effectScope()` is flat only** — no nested scopes, no `detached`
  option. Every scope is independent; stopping one never cascades
  into another. See [`effectScope()`](08-effect-scope.md).
- **`computed()`'s scope behavior isn't a Vue concept.** `computed()`
  values here *are* collected by an active `effectScope()`, matching
  Vue's own self-registration behavior. But what `scope:stop()` does
  with a collected `computed()` is this library's own invention:
  rather than destroying it the way `effect()`/`watch()` are
  destroyed, it's only frozen — its last value stays valid and
  readable forever for anything still depending on it. Vue's own
  computed values don't distinguish "stopped" from "destroyed" this
  way. See [`effectScope()`](08-effect-scope.md#computed-is-collected-too--with-one-twist).
- **No real 4-way variant composition** for `reactive()`/`readonly()`
  and friends. In Vue, `readonly(reactive(x))` gives you a genuine
  readonly wrapper around a reactive proxy. Here, calling any variant
  constructor on something that's already some reactive-family proxy
  just returns that existing proxy unchanged, regardless of which
  variant you asked for — see
  [Reactive variants](07-reactive-variants.md).
- **`isReactive()` doesn't exclude readonly proxies.** Vue's version
  specifically distinguishes "is this reactive" from "is this
  readonly." Here, `isReactive()` is simply true for any of the four
  variants; use `isReadonly()` for the finer-grained check.
- **`toRef()`'s getter form doesn't cache.** Vue wraps a getter
  function in an internal `computed()` for caching. This library just
  calls the getter directly on every read — simpler, and correct for
  the common case, but worth knowing if your getter is expensive and
  read often between actual changes.

## Not built yet

- **`customRef`** — straightforward to add if it's ever needed, just
  hasn't come up yet.

## What's kept faithfully

Not everything is different, to be clear — the actual clever part of
Vue's design, the linked-list dependency tracking (`Dep`/`Link`), is
ported closely to the original, because it's genuinely good
engineering and translates cleanly to Lua. Batching, dirty-checking,
and the overall shape of how effects, refs, and computeds interact
all follow the same design Vue uses. The differences above are
specifically the parts that were either JS/DOM-specific, or where a
simpler approach served this project just as well without giving up
anything it actually needed.
