# `effectScope()`

Stopping one `effect()` or `watch()` at a time is fine when you've
only got one. But once you've got several related effects/watchers
that logically belong together — all set up for the same "thing" and
all needing to go away at the same time — tracking down every runner
and handle to stop them one by one gets tedious and error-prone.
`effectScope()` fixes that: stop the scope, everything inside it
stops too.

## The basic idea

```lua
local reactive = require("reactive")
local effectScope = reactive.effectScope
local effect = reactive.effect
local watchEffect = reactive.watchEffect

local scope = effectScope()

scope:run(function()
  effect(function()
    print("effect A")
  end)
  watchEffect(function()
    print("effect B")
  end)
end)

scope:stop()   -- both effects above are stopped, in one call
```

Anything created via `effect()`, `watch()`, or `watchEffect()` while
`scope:run(fn)` is executing gets automatically collected by that
scope. You don't have to hang on to individual runners or handles —
just stop the scope.

## Cleaning up more than just effects

If you've got other cleanup to do — closing a file handle, canceling
a subscription, whatever — that isn't itself an effect,
`onScopeDispose()` lets you hook into the same `stop()` call:

```lua
local onScopeDispose = reactive.onScopeDispose

local connScope = effectScope()

connScope:run(function()
  local connection = openSomeConnection()
  onScopeDispose(function()
    connection:close()
  end)

  watchEffect(function()
    -- do something with the connection
  end)
end)

connScope:stop()   -- closes the connection AND stops the watcher above
```

Dispose callbacks run in reverse order (last registered, first run) —
right before the scope's effects are torn down.

## A practical pattern

If you're building something with a lifecycle — imagine a
self-contained "widget" that sets up some reactive behavior and needs
to clean up completely when it's done — a scope per instance is a
natural fit:

```lua
local makeReactive = reactive.reactive

local function createWidget()
  local scope = effectScope()
  local state = makeReactive({ visible = true })

  scope:run(function()
    watchEffect(function()
      print("widget visibility:", state.visible)
    end)
  end)

  return {
    state = state,
    destroy = function() scope:stop() end,
  }
end

local widget = createWidget()
widget.state.visible = false   -- watcher reacts, prints the new state
widget.destroy()                -- everything the widget set up is cleaned up
```

## `computed()` is collected too — with one twist

Any `computed()` created inside `scope:run()` is automatically
collected by the scope, same as `effect()`/`watch()`/`watchEffect()`.
But `scope:stop()` treats it a little differently: `effect()` and
`watch()`/`watchEffect()` are fully torn down and never usable again,
while a `computed()` is only *frozen* — its last value stays valid
and readable forever, it just stops recalculating (this is exactly
`computed()`'s own [`:stop()`](03-computed.md#stopping-and-pausing-a-computed)
being called on your behalf). Nothing else that depends on that
computed breaks when the scope stops — it just keeps reading
whatever value the computed landed on.

## Pausing and resuming a whole scope

Stopping is permanent. If what you actually want is to temporarily
freeze everything in a scope — without losing the dependency
structure, so there's nothing to rebuild afterward — `scope:pause()`
and `scope:resume()` do exactly that:

```lua
local uiScope = effectScope()
local panelState = makeReactive({ items = 3 })

uiScope:run(function()
  watchEffect(function()
    print("panel has", panelState.items, "items")
  end)
end)

uiScope:pause()              -- the watcher above stops reacting
panelState.items = 10        -- no reaction, still paused

uiScope:resume()             -- picks back up, catches up on what it missed
```

This is the natural fit for something like a UI panel that gets
hidden and shown again: pause everything in its scope when it's
hidden (no point reacting to changes nobody can see), resume when
it's visible again — one call each way, no rebuilding any watchers
or effects from scratch.

## `getCurrentScope()`

If you're writing something reusable that should register itself into
whatever scope happens to be active — without that code needing to
know or care which scope that is — `getCurrentScope()` gives you a
handle to it (or `nil`, if nothing's currently running inside a
`scope:run(fn)`). Most everyday code won't need this directly; it's
more useful for library-style building blocks.

## For Vue folks

> **For Vue folks:** this is the flat case only — no scope nesting,
> no `detached` option. Creating a scope while another is already
> running doesn't make it a child of the outer one, and stopping the
> outer scope won't cascade into the inner one. `computed()` values
> *are* collected by a scope here, same as in Vue — but the
> "stop means freeze, not destroy" distinction for `computed()`
> specifically isn't a Vue concept; that part is this library's own
> design choice.

## Reference

Full signatures and details: [`reference/scope.md`](reference/scope.md).
