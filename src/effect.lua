--[[
  reactive/effect.lua -- ReactiveEffect, batching, dirty-checking
  Version: 3 -- see VERSIONS.md (repo root) before editing this file.

  See NOTES.md (repo root) first if you haven't already. Design ported
  from Vue 3's @vue/reactivity effect.ts -- full credit to the Vue.js
  team. Rewrite, not a copy: no scheduler/onTrack/onTrigger debug hooks,
  no __DEV__ branches, no pausedQueueEffects WeakSet (plain table with
  identity keys instead, Lua has no WeakSet but this project doesn't
  need GC-awareness here -- pause/resume is explicit user action, not
  something that needs to happen automatically at GC time).
]]

local dep_module = require("reactive.dep")

local M = {}

-- scope.lua requires THIS file (reactive.effect) at module top level
-- (ReactiveEffect.new() is what an EffectScope actually collects), so
-- this file cannot require("reactive.scope") at ITS top level too --
-- same class of cycle already solved between dep.lua/effect.lua and
-- ref.lua/reactive.lua (see docs/dep.lua.md, docs/ref.lua.md). Fix:
-- lazy, memoized require inside a function body, same convention as
-- getReactiveModule() in ref.lua -- this is the third occurrence of
-- this pattern, formally promoted to a documented project convention
-- in ARCHITECTURE.md as of this file's v3 (was already flagged as
-- "should be promoted" in an earlier session's PROGRESS.md entry).
local scope_module = nil
local function getScopeModule()
  if not scope_module then
    scope_module = require("reactive.scope")
  end
  return scope_module
end

-- ===========================================================================
-- EffectFlags (bitflags -- Lua 5.4 has native bitwise operators)
-- ===========================================================================

--- ported from effect.ts's `EffectFlags` enum
M.EffectFlags = {
  ACTIVE = 1 << 0,
  RUNNING = 1 << 1,
  TRACKING = 1 << 2,
  NOTIFIED = 1 << 3,
  DIRTY = 1 << 4,
  ALLOW_RECURSE = 1 << 5,
  PAUSED = 1 << 6,
}
local EffectFlags = M.EffectFlags

-- ===========================================================================
-- module-level tracking state
-- ===========================================================================

-- the Subscriber currently running (effect or computed), or nil
-- ported from effect.ts's `activeSub`
M.activeSub = nil

-- whether dep access should currently be tracked at all
-- ported from effect.ts's `shouldTrack`
M.shouldTrack = true
local trackStack = {}

-- Temporarily pauses tracking; must be paired with a later resetTracking().
function M.pauseTracking()
  trackStack[#trackStack + 1] = M.shouldTrack
  M.shouldTrack = false
end

-- Re-enables tracking; must be paired with a later resetTracking().
function M.enableTracking()
  trackStack[#trackStack + 1] = M.shouldTrack
  M.shouldTrack = true
end

-- Restores whatever tracking state was active before the last
-- pauseTracking()/enableTracking() call.
function M.resetTracking()
  local n = #trackStack
  if n == 0 then
    M.shouldTrack = true
  else
    M.shouldTrack = trackStack[n]
    trackStack[n] = nil
  end
end

-- ===========================================================================
-- batching
-- ===========================================================================

local batchDepth = 0
local batchedSub = nil
local batchedComputed = nil

--- Queues a subscriber to be notified once the outermost batch ends.
--- isComputed: computed subscribers are queued separately and flushed
--- first (their NOTIFIED flag just gets cleared, they don't "trigger" --
--- a computed only recomputes lazily on next .value read).
--- ported from effect.ts's `batch()`
function M.batch(sub, isComputed)
  sub.flags = sub.flags | EffectFlags.NOTIFIED
  if isComputed then
    sub.nextBatch = batchedComputed
    batchedComputed = sub
    return
  end
  sub.nextBatch = batchedSub
  batchedSub = sub
end

-- ported from effect.ts's `startBatch()`
function M.startBatch()
  batchDepth = batchDepth + 1
end

-- Runs batched effects once all nested batches have ended.
-- ported from effect.ts's `endBatch()`
function M.endBatch()
  batchDepth = batchDepth - 1
  if batchDepth > 0 then
    return
  end

  local e, nextE
  if batchedComputed then
    e = batchedComputed
    batchedComputed = nil
    while e do
      nextE = e.nextBatch
      e.nextBatch = nil
      e.flags = e.flags & ~EffectFlags.NOTIFIED
      e = nextE
    end
  end

  local err, firstError, ok
  while batchedSub do
    e = batchedSub
    batchedSub = nil
    while e do
      nextE = e.nextBatch
      e.nextBatch = nil
      e.flags = e.flags & ~EffectFlags.NOTIFIED
      if e.flags & EffectFlags.ACTIVE ~= 0 then
        ok, err = pcall(e.trigger, e)
        if not ok and not firstError then
          firstError = err
        end
      end
      e = nextE
    end
  end

  if firstError then
    error(firstError, 0)
  end
end

-- ===========================================================================
-- dep-list bookkeeping shared by effects and computed
-- ===========================================================================

--- Marks all of a subscriber's current deps as "unconfirmed" (version
--- -1) before a run, and points each dep's activeLink at the
--- corresponding link so Dep:track() can find/reuse it during the run.
--- ported from effect.ts's `prepareDeps()`
local function prepareDeps(sub)
  local link = sub.deps
  while link do
    link.version = -1
    link.prevActiveLink = link.dep.activeLink
    link.dep.activeLink = link
    link = link.nextDep
  end
end

-- After a run, removes any dep links that stayed unconfirmed (version
-- still -1, meaning that dep wasn't read this run) from both linked
-- lists, and restores each dep's previous activeLink.
-- ported from effect.ts's `cleanupDeps()`
local function cleanupDeps(sub)
  local tail = sub.depsTail
  local link = tail
  local head, prev, prevDep, nextDep
  while link do
    prev = link.prevDep
    if link.version == -1 then
      if link == tail then
        tail = prev
      end
      dep_module.removeSub(link)
      -- unlink from sub's own dep list too
      prevDep = link.prevDep
      nextDep = link.nextDep
      if prevDep then
        prevDep.nextDep = nextDep
        link.prevDep = nil
      end
      if nextDep then
        nextDep.prevDep = prevDep
        link.nextDep = nil
      end
    else
      head = link
    end

    link.dep.activeLink = link.prevActiveLink
    link.prevActiveLink = nil
    link = prev
  end
  sub.deps = head
  sub.depsTail = tail
end

--- Whether any of sub's deps changed since it last ran (or, for a dep
--- that belongs to a computed, whether that computed itself needs
--- refreshing first).
--- ported from effect.ts's `isDirty()`
local function isDirty(sub)
  local link = sub.deps
  while link do
    if link.dep.version ~= link.version then
      return true
    end
    if link.dep.computed and (M.refreshComputed(link.dep.computed) or link.dep.version ~= link.version) then
      return true
    end
    link = link.nextDep
  end
  return false
end
M.isDirty = isDirty

-- Re-evaluates a computed if needed (its own deps changed, or it was
-- never evaluated). No-op if nothing relevant changed since last time.
-- ported from effect.ts's `refreshComputed()`
-- Requires `computed` to look like ref.lua's ComputedRefImpl: fields
-- flags, globalVersion, dep, deps, fn, value.
function M.refreshComputed(computed)
  if computed.flags & EffectFlags.TRACKING ~= 0 and computed.flags & EffectFlags.DIRTY == 0 then
    return
  end
  computed.flags = computed.flags & ~EffectFlags.DIRTY

  -- fast path: nothing at all changed globally since we last refreshed
  if computed.globalVersion == dep_module.globalVersion then
    return
  end
  computed.globalVersion = dep_module.globalVersion

  local dep = computed.dep
  computed.flags = computed.flags | EffectFlags.RUNNING

  if dep.version > 0 and computed.deps and not isDirty(computed) then
    computed.flags = computed.flags & ~EffectFlags.RUNNING
    return
  end

  local prevSub = M.activeSub
  local prevShouldTrack = M.shouldTrack
  M.activeSub = computed
  M.shouldTrack = true

  local ok, err = pcall(function()
    prepareDeps(computed)
    local newValue = computed.fn(computed._value)
    if dep.version == 0 or newValue ~= computed._value then
      computed._value = newValue
      dep.version = dep.version + 1
    end
  end)

  M.activeSub = prevSub
  M.shouldTrack = prevShouldTrack
  cleanupDeps(computed)
  computed.flags = computed.flags & ~EffectFlags.RUNNING

  if not ok then
    dep.version = dep.version + 1
    error(err, 0)
  end
end

-- ===========================================================================
-- ReactiveEffect
-- ===========================================================================

--- ported from effect.ts's `ReactiveEffect` class
local ReactiveEffect = {}
ReactiveEffect.__index = ReactiveEffect
M.ReactiveEffect = ReactiveEffect

local pausedEffects = setmetatable({}, { __mode = "k" }) -- weak-keyed set of paused-while-triggered effects

--- ported from effect.ts's `ReactiveEffect` constructor, which pushes
--- itself into `activeEffectScope.effects` when a scope is active --
--- see getScopeModule() above for why this is a lazy require instead of
--- a top-level one.
function ReactiveEffect.new(fn)
  local self = setmetatable({
    fn = fn,
    deps = nil,
    depsTail = nil,
    flags = EffectFlags.ACTIVE | EffectFlags.TRACKING,
    nextBatch = nil,
    cleanupFn = nil,
    scheduler = nil,
  }, ReactiveEffect)

  local activeScope = getScopeModule().activeEffectScope
  if activeScope then
    activeScope:_recordEffect(self)
  end

  return self
end

function ReactiveEffect:pause()
  self.flags = self.flags | EffectFlags.PAUSED
end

function ReactiveEffect:resume()
  if self.flags & EffectFlags.PAUSED == 0 then return end
  self.flags = self.flags & ~EffectFlags.PAUSED
  if pausedEffects[self] then
    pausedEffects[self] = nil
    self:trigger()
  end
end

-- Called by a Dep when one of this effect's deps changes. Queues the
-- effect into the current batch unless it's already queued or
-- currently running without allowing recursion.
-- ported from effect.ts's `ReactiveEffect:notify()`
function ReactiveEffect:notify()
  if self.flags & EffectFlags.RUNNING ~= 0 and self.flags & EffectFlags.ALLOW_RECURSE == 0 then
    return
  end
  if self.flags & EffectFlags.NOTIFIED == 0 then
    M.batch(self, false)
  end
end

local function cleanupEffect(e)
  local cleanupFn = e.cleanupFn
  e.cleanupFn = nil
  if not cleanupFn then return end
  local prevSub = M.activeSub
  M.activeSub = nil
  local ok, err = pcall(cleanupFn)
  M.activeSub = prevSub
  if not ok then
    error(err, 0)
  end
end

-- Runs fn with this effect as the active subscriber, tracking every
-- dep it reads. Returns fn's return value.
-- ported from effect.ts's `ReactiveEffect:run()`
function ReactiveEffect:run()
  if self.flags & EffectFlags.ACTIVE == 0 then
    -- stopped -- just run fn without any tracking
    return self.fn()
  end

  self.flags = self.flags | EffectFlags.RUNNING
  cleanupEffect(self)
  prepareDeps(self)
  local prevSub = M.activeSub
  local prevShouldTrack = M.shouldTrack
  M.activeSub = self
  M.shouldTrack = true

  local ok, result = pcall(self.fn)

  cleanupDeps(self)
  M.activeSub = prevSub
  M.shouldTrack = prevShouldTrack
  self.flags = self.flags & ~EffectFlags.RUNNING

  if not ok then
    error(result, 0)
  end
  return result
end

-- Stops the effect: unlinks it from all its deps and marks it inactive.
-- ported from effect.ts's `ReactiveEffect:stop()`
function ReactiveEffect:stop()
  if not (self.flags & EffectFlags.ACTIVE ~= 0) then return end
  local link = self.deps
  while link do
    dep_module.removeSub(link)
    link = link.nextDep
  end
  self.deps = nil
  self.depsTail = nil
  cleanupEffect(self)
  if self.onStop then
    self.onStop()
  end
  self.flags = self.flags & ~EffectFlags.ACTIVE
end

-- Called when a dep this effect subscribes to changes. Runs the
-- scheduler if one is set, otherwise re-runs the effect if it's dirty.
-- ported from effect.ts's `ReactiveEffect:trigger()`
function ReactiveEffect:trigger()
  if self.flags & EffectFlags.PAUSED ~= 0 then
    pausedEffects[self] = true
  elseif self.scheduler then
    self.scheduler()
  else
    self:runIfDirty()
  end
end

function ReactiveEffect:runIfDirty()
  if isDirty(self) then
    self:run()
  end
end

function ReactiveEffect:dirty()
  return isDirty(self)
end

-- ===========================================================================
-- public effect() / stop() API
-- ===========================================================================

--- Creates and immediately runs a ReactiveEffect wrapping fn. Returns a
--- runner: calling it re-runs fn (still tracked); runner.effect gives
--- access to the underlying ReactiveEffect (for :stop(), :pause(), etc).
--- options: optional table, may set `scheduler`.
--- ported from effect.ts's `effect()`
function M.effect(fn, options)
  local e = ReactiveEffect.new(fn)
  if options then
    if options.scheduler ~= nil then
      e.scheduler = options.scheduler
    end
    if options.onStop ~= nil then
      e.onStop = options.onStop
    end
  end

  local ok, err = pcall(e.run, e)
  if not ok then
    e:stop()
    error(err, 0)
  end

  -- Lua functions can't carry extra fields (unlike JS functions), so
  -- the runner is a callable table instead: `runner()` re-runs the
  -- effect, `runner.effect` exposes the underlying ReactiveEffect.
  local runner = setmetatable({ effect = e }, {
    __call = function()
      return e:run()
    end,
  })
  return runner
end

-- Stops the effect associated with a runner returned by M.effect().
function M.stop(runner)
  runner.effect:stop()
end

-- Registers a cleanup function on the currently running effect. Called
-- right before the next run, or when the effect is stopped.
-- ported from effect.ts's `onEffectCleanup()`
function M.onEffectCleanup(fn, failSilently)
  if M.activeSub and getmetatable(M.activeSub) == ReactiveEffect then
    M.activeSub.cleanupFn = fn
  elseif not failSilently then
    error("onEffectCleanup() was called when there was no active effect to associate with.", 2)
  end
end

return M
