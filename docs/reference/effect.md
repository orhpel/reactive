# `effect`

See [`ref()` and `effect()`](../02-ref-and-effect.md) for an
introduction to `effect`, `stop`, and `onEffectCleanup` with examples.
See [Tracking control](../12-tracking-control.md) for an introduction
to `pauseTracking`, `enableTracking`, and `resetTracking` (documented
further down in this same file) with examples.

---

## `reactive.effect(fn, options?)`

```
reactive.effect(fn, options?) -> runner
```

Runs `fn` immediately, then re-runs it automatically whenever any
ref, computed, or reactive property read *during the run* later
changes. Dependencies are re-discovered fresh on every run — if `fn`
reads different things on a later run (say, behind an `if`), the
tracked dependency set updates to match.

Returns a **runner**: a callable value where `runner()` re-runs `fn`
manually (still tracked normally), and `runner.effect` is the
underlying effect object — use it for `:stop()`, `:pause()`, and
`:resume()`.

`options` (optional table):

| Key | Purpose |
|---|---|
| `scheduler` | A function called instead of immediately re-running `fn` on trigger. Receives no arguments; call `runner()` yourself from inside it if/when you want the actual re-run. Used internally by [`watch()`](watch.md) to control *when* the callback fires — most everyday code won't need this. |
| `onStop` | Called once, when the effect is stopped via `:stop()`. |

## `reactive.stop(runner)`

```
reactive.stop(runner) -> nil
```

Stops the effect behind `runner`. Equivalent to
`runner.effect:stop()`. After this, the effect never re-runs again,
no matter what changes.

## `reactive.onEffectCleanup(fn, failSilently?)`

```
reactive.onEffectCleanup(fn, failSilently?) -> nil
```

Registers `fn` as a cleanup callback for the **currently running**
effect. Runs right before that effect's next re-run, and also when
the effect is stopped — the usual place to tear down anything the
effect set up (timers, subscriptions, and the like).

Must be called from inside an actively running effect. If there is no
active effect:

- `failSilently` not set (or falsy): raises an error.
- `failSilently = true`: silently does nothing.

## `reactive.pauseTracking()`

```
reactive.pauseTracking() -> nil
```

Temporarily turns tracking off — any reactive value read after this
call, until the matching `resetTracking()`, does **not** become a
dependency of the currently running effect/watcher. Pushes the
previous tracking state onto an internal stack; must always be paired
with a later `resetTracking()`.

## `reactive.enableTracking()`

```
reactive.enableTracking() -> nil
```

The mirror of `pauseTracking()` — forces tracking back on, even
inside a block where it's currently paused. Also pushes onto the same
stack; also must be paired with a later `resetTracking()`.

## `reactive.resetTracking()`

```
reactive.resetTracking() -> nil
```

Restores tracking to whatever state was active before the most recent
unmatched `pauseTracking()`/`enableTracking()` call (pops the stack
pushed by either of those). Calling it with nothing on the stack
resets tracking to "on."

These three are available directly at the top level
(`reactive.pauseTracking()` and so on) — see
[Tracking control](../12-tracking-control.md) for when you'd actually
want to use them (rarely).
