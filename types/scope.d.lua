---@meta scope

-- effectScope() / scope lifecycle / onScopeDispose().
-- Design ported from Vue 3's @vue/reactivity effectScope.ts.
-- Deliberately flat only: no nested/parent-child scopes, no `detached`,
-- no public `effects`/`cleanups` fields exposed as API.

---A disposal-grouping scope. Anything registered while the scope is
---active (currently only ReactiveEffect-based subscribers — effect()
---and watch()/watchEffect()) is torn down by :stop(). computed() is
---deliberately NOT scope-collected in this project.
---@class Reactive.EffectScope
---@field __index Reactive.EffectScope
---@field active boolean True until :stop() is called. Public boolean field.
---@field effects Reactive.ReactiveEffect[] Internal list of subscribers collected while this scope was active.
---@field cleanups function[]? Internal list of onScopeDispose() callbacks (LIFO on stop). Created lazily.
local EffectScope = {}

---Constructs a new EffectScope, starting active.
---@return Reactive.EffectScope
function EffectScope.new() end

--- Registers a subscriber (anything effect.lua's ReactiveEffect.new()
--- produces -- includes watch()/watchEffect() watchers, since those are
--- built on ReactiveEffect too) into this scope's effect list. Called
--- by ReactiveEffect.new() itself, not meant to be called directly by
--- user code.
---@param sub Reactive.ReactiveEffect
function EffectScope:_recordEffect(sub) end

--- Runs fn with this scope active, so any effect()/computed()/watch()/
--- watchEffect() created during fn gets collected into this scope.<br/>
--- Returns fn's return value, or nil if the scope was already stopped.<br/>
--- *matches Vue: an inactive scope's run() is a no-op, not an error*
---@param fn function
---@return any
function EffectScope:run(fn) end

--- Stops every effect collected by this scope, runs every
--- onScopeDispose() callback registered against it (LIFO, matching
--- Vue), and marks the scope inactive. Idempotent: calling stop() on an
--- already-stopped scope is a no-op, same as ReactiveEffect:stop().
function EffectScope:stop() end

---Public surface of `reactive.scope`.
---@class Reactive.ScopeModule
---@field EffectScope Reactive.EffectScope
---@field activeEffectScope Reactive.EffectScope? The currently-running scope, or nil.
local M = {}

---Creates a new scope, starting active.
---@return Reactive.EffectScope
function M.effectScope() end

---Returns the currently-running scope (innermost active run(fn)), or
---nil if none is active.
---@return Reactive.EffectScope?
function M.getCurrentScope() end

--- Registers a dispose callback against the currently active scope
--- (i.e. called from within a scope:run(fn)). Called right before that
--- scope's effects are stopped, in LIFO order, when the scope is
--- stopped. failSilently: if true, do nothing (no error) when there's
--- no active scope to attach to -- mirrors onEffectCleanup()'s and
--- onWatcherCleanup()'s own failSilently parameter for consistency.
---@param fn Reactive.CleanupFn
---@param failSilently? boolean
function M.onScopeDispose(fn, failSilently) end

return M