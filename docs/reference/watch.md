# `watch`

See [`watch()` and `watchEffect()`](../05-watch.md) for an
introduction with examples. See
[Deep watching](../09-deep-watching.md) for the full `deep` option
detail, documented further down in this same file.

---

## `reactive.watch(source, cb, options?)`

```
reactive.watch(source, cb, options?) -> WatchHandle
```

Watches `source` and calls `cb(newValue, oldValue, onCleanup)` when it
changes.

`source` can be:

- a ref (or computed)
- a `reactive()` table
- a zero-argument getter function

**Not supported:** multiple sources in one call (no `watch({a, b}, cb)`
form) — call `watch()` once per source instead.

`cb(newValue, oldValue, onCleanup)`:

- `oldValue` is `nil` on the very first call if `options.immediate`
  is set. On every subsequent call, it's the actual previous value.
- `onCleanup(fn)` registers `fn` to run right before the *next* time
  `cb` fires, or when the watcher is stopped.

`options` (optional table):

| Key | Effect |
|---|---|
| `immediate` | Run `cb` once immediately, in addition to on future changes. `oldValue` is `nil` on that first call. |
| `once` | Automatically stop the watcher after `cb`'s first run. |
| `deep` | Watch nested changes too, not just the top-level value. `true`/`false`, or a non-negative integer for a depth limit. See "The `deep` option" below and [Deep watching](../09-deep-watching.md). |

Returns a **WatchHandle**: callable directly to stop (`handle()`),
plus explicit methods:

| Method | Effect |
|---|---|
| `handle:stop()` | Same as calling `handle()` — stops the watcher for good. |
| `handle:pause()` | Temporarily stops reacting to changes. |
| `handle:resume()` | Resumes; catches up on anything that changed while paused. |

### The `deep` option, precisely

- `deep` omitted, `source` is a `reactive()` table: fully unlimited
  depth. (This is the "deep by default" behavior — no options
  needed.)
- `deep` omitted, `source` is anything else (ref, computed, getter):
  no descent at all — only the top-level value itself is compared.
- `deep = true`: unlimited depth, regardless of source type.
- `deep = false`: same as omitting it for a non-`reactive()` source
  (no descent). For a `reactive()` source, this **narrows** the
  otherwise-implicit unlimited depth down to root-level only —
  equivalent to `deep = 0`.
- `deep = N` (a non-negative integer): descends `N` levels below the
  root. `N = 0` still reads (and reacts to changes on) the root
  value's own keys — it just never looks inside any of those keys'
  own values. A negative number raises an error immediately.

**Reference-identity note:** when deep tracking is active and the
value returned is itself a `reactive()` proxy, `cb`'s `newValue` and
`oldValue` are the same object reference (a `reactive()` proxy is
always the same reference across reads) — the fact that the watcher
fired at all is the signal that something changed, not a reference
comparison. See [Deep watching](../09-deep-watching.md) for the full
explanation with an example.

## `reactive.watchEffect(fn, options?)`

```
reactive.watchEffect(fn, options?) -> WatchHandle
```

Runs `fn(onCleanup)` immediately and re-runs it whenever anything it
reads (refs, computed values, or `reactive()` properties) later
changes. Unlike `watch()`, there's no separate source — whatever `fn`
reads *is* what gets tracked, discovered fresh on every run, same as
`effect()`.

`options` (optional table):

| Key | Effect |
|---|---|
| `once` | Automatically stop after the first run's dependencies trigger a re-run once. (There's no `immediate` option here — `watchEffect()` is always immediate by definition.) |

Returns the same kind of **WatchHandle** as `watch()`.

## `reactive.onWatcherCleanup(fn, failSilently?)`

```
reactive.onWatcherCleanup(fn, failSilently?) -> nil
```

The free-function form of registering a cleanup — normally you'd use
the `onCleanup` parameter passed into `cb`/`fn` instead, but this is
available directly if needed. Must be called while a watcher is
actively running.

- `failSilently` not set (or falsy): raises an error if there's no
  active watcher.
- `failSilently = true`: silently does nothing instead.
