---@meta effect

-- ReactiveEffect, EffectFlags, tracking/batching state.
-- Design ported from Vue 3's @vue/reactivity effect.ts.

---Bitfield flags describing a ReactiveEffect's or computed's state.
---Combine with bitwise operators (`flags & Reactive.EffectFlags.DIRTY`).
---@class Reactive.ReactiveEffectFlags
---@field ACTIVE integer Effect is active (not stopped).
---@field RUNNING integer Effect is currently running its function.
---@field TRACKING integer Effect wants to track deps it reads.
---@field NOTIFIED integer Effect is already queued in the current batch.
---@field DIRTY integer Effect's deps have changed since its last run.
---@field ALLOW_RECURSE integer Permit re-entrant trigger while RUNNING is set.
---@field PAUSED integer Effect is paused; triggers are held until :resume().
local EffectFlags = {}

---Callback function that is called once when the effect stops.
---@alias Reactive.ReactiveEffect.StopFn function

---Callback function that is called instead of immediately
---re-running the effect.
---@alias Reactive.ReactiveEffect.SchedulerFn function

---Optional table; may set `scheduler` and/or `onStop`.
---@class Reactive.ReactiveEffectOptions : table
---@field onStop Reactive.ReactiveEffect.StopFn?
---@field scheduler Reactive.ReactiveEffect.SchedulerFn?

---An effect: runs `fn`, tracks every reactive value read during the
---run, and re-runs when any of those change.
---@class Reactive.ReactiveEffect : Reactive.Subscriber
---@field cleanupFn Reactive.CleanupFn?
---@field deps Reactive.Link? Head of the effect's dep list.
---@field depsTail Reactive.Link? Tail of the effect's dep list.
---@field flags integer Bitfield of EffectFlags.
---@field fn function The effect's body function.
---@field nextBatch Reactive.Link? Next link in the batching queue.
---@field onStop Reactive.ReactiveEffect.StopFn
---@field scheduler Reactive.ReactiveEffect.SchedulerFn?
local ReactiveEffect = {}

---Constructs a new ReactiveEffect wrapping `fn`. If a scope is
---currently active, the effect is auto-registered into it.
---@param fn function Effect body.
---@return Reactive.ReactiveEffect
function ReactiveEffect.new(fn) end

---Suspends recomputation (sets the PAUSED flag). A trigger while paused
---is recorded and deferred to :resume().
function ReactiveEffect:pause() end

---Reverses :pause(). If anything changed while paused, triggers the
---effect immediately (synchronously through the normal batch machinery).
function ReactiveEffect:resume() end

--- Called by a Dep when one of this effect's deps changes. Queues the
--- effect into the current batch unless it's already queued or
--- currently running without allowing recursion.
function ReactiveEffect:notify() end

---Runs `fn` with this effect as the active subscriber, tracking every
---dep it reads. Returns fn's return value.
---@return any
function ReactiveEffect:run() end

---Stops the effect: unlinks it from all deps, runs any cleanup, fires
---`onStop`, and clears the ACTIVE flag.
function ReactiveEffect:stop() end

---Called when a dep this effect subscribes to changes. Runs the
---scheduler if one is set, otherwise re-runs the effect if dirty.
function ReactiveEffect:trigger() end

---Runs the effect immediately if isDirty() is true.
function ReactiveEffect:runIfDirty() end

---Whether any dep has changed since the effect's last run.
---@return boolean
function ReactiveEffect:dirty() end

---Callable wrapper returned by `effect()`. Calling `runner()` re-runs
---the effect (still tracked); `runner.effect` exposes the underlying
---ReactiveEffect for :stop() / :pause() / :resume().
---@class Reactive.Runner
---@field effect Reactive.ReactiveEffect Underlying effect instance.
local Runner = {}

---Public surface of `reactive.effect`.
---@class Reactive.EffectModule
---@field EffectFlags Reactive.ReactiveEffectFlags
---@field ReactiveEffect Reactive.ReactiveEffect
---@field activeSub Reactive.Subscriber? Subscriber currently running, or nil.
---@field shouldTrack boolean Whether dep reads should be tracked at all.
local M = {}

--- Queues a subscriber to be notified once the outermost batch ends.
--- isComputed: computed subscribers are queued separately and flushed
--- first (their NOTIFIED flag just gets cleared, they don't "trigger" --
--- a computed only recomputes lazily on next .value read).
---@param sub Reactive.Subscriber
---@param isComputed any If truthy, queue into the computed list instead.
function M.batch(sub, isComputed) end

---Opens a new batch (nested batches coalesce).
function M.startBatch() end

---Closes the current batch; when depth reaches zero, flushes queued
---computed and effect notifications.
function M.endBatch() end

---Pushes the current tracking state and disables tracking. Must be
---paired with a later resetTracking().
function M.pauseTracking() end

---Pushes the current tracking state and forces tracking on. Must be
---paired with a later resetTracking().
function M.enableTracking() end

---Restores the tracking state saved by the most recent pauseTracking()
---or enableTracking() call.
function M.resetTracking() end

-- Re-evaluates a computed if needed (its own deps changed, or it was
-- never evaluated). No-op if nothing relevant changed since last time.
-- ported from effect.ts's `refreshComputed()`
-- Requires `computed` to look like ref.lua's ComputedRefImpl: fields
-- flags, globalVersion, dep, deps, fn, value.
---@param computed Reactive.ComputedRef
function M.refreshComputed(computed) end

--- Whether any of sub's deps changed since it last ran (or, for a dep
--- that belongs to a computed, whether that computed itself needs
--- refreshing first).
---@param sub Reactive.Subscriber
---@return boolean
function M.isDirty(sub) end

--- Creates and immediately runs a ReactiveEffect wrapping fn. Returns a
--- runner: calling it re-runs fn (still tracked); runner.effect gives
--- access to the underlying ReactiveEffect (for :stop(), :pause(), etc).
--- options: optional table, may set `scheduler`.
---@param fn function
---@param options Reactive.ReactiveEffectOptions?
---@return Reactive.Runner
function M.effect(fn, options) end

---Stops the effect behind a runner. Equivalent to `runner.effect:stop()`.
---@param runner Reactive.Runner
function M.stop(runner) end

---Registers a cleanup function against the currently running effect.
---Runs right before the effect's next run, or when it is stopped.
---@param fn Reactive.CleanupFn Cleanup callback.
---@param failSilently? boolean If true, no error when there is no active effect.
function M.onEffectCleanup(fn, failSilently) end

return M