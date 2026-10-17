--[[
  reactive/scope.lua -- EffectScope
  Version: 1 -- see VERSIONS.md (repo root) before editing this file.

  See NOTES.md (repo root) first if you haven't already. Design ported
  from Vue 3's @vue/reactivity effectScope.ts -- full credit to the
  Vue.js team. Rewrite, not a copy.

  DELIBERATE SIMPLIFICATION, per Lephro's own call: this is the FLAT
  case only. Concretely dropped, and why:

  - NO nested scopes / parent-child tree. Vue's EffectScope can nest
    (a scope created while another is active registers itself as a
    child, and stopping the parent recursively stops all children).
    That machinery touches every method (registration bookkeeping,
    stop-order, an index-based O(1) child-removal, the `detached`
    escape hatch to opt out of auto-nesting) for a feature this project
    doesn't need yet -- the GUI layer that would want scope-per-
    component nesting doesn't exist yet and its shape isn't decided.
    Deliberately deferred, not silently unsupported: pull this file up
    again if/when the GUI project actually needs nested disposal, and
    write the tests against ITS real requirements rather than Vue's.
  - NO `detached` option -- meaningless without nesting to detach from.
  - NO `scope.effects` / `scope.cleanups` arrays exposed as public
    fields (Vue exposes these, mainly for its own test suite). This
    file tracks the same information internally but doesn't promise it
    as API surface -- nothing in this project's usage needs to inspect
    a scope's collected effects from outside.

  Kept: run(fn), stop(), active flag, getCurrentScope(),
  onScopeDispose() -- the actual disposal-grouping mechanism, which is
  the whole point of this module.

  ## How registration works

  `ReactiveEffect.new()` (effect.lua) checks M.activeEffectScope (this
  module's currently-running scope, or nil) and, if set, registers
  itself into that scope's effect list -- mirroring effect.ts's own
  `activeEffectScope` push-on-construction. watch()/watchEffect()
  (watch.lua) build their watcher via `effect.ReactiveEffect.new()`
  too, so they pick this up for free with no changes of their own --
  verified in scope_spec.lua rather than assumed, since "the ownership
  wires up correctly across module boundaries" is exactly the kind of
  claim worth checking, not asserting.

  ## computed() is DELIBERATELY NOT scope-collected (deviates from Vue)

  Vue's ComputedRefImpl also registers itself into activeEffectScope on
  construction. This project's ComputedRefImpl (ref.lua) does NOT --
  and can't, without further work, because unlike ReactiveEffect it has
  no :stop() method at all today (a computed here just stops mattering
  once nothing reads its .value / its deps are gone; there was never a
  need for explicit teardown before this file existed). Rather than
  bolt on a stub :stop() just to satisfy this module's registration
  contract, computed() construction was left untouched. Consequence:
  `scope:run(function() local c = computed(...) end)` does NOT put `c`
  under that scope's stop() -- only effect()/watch()/watchEffect() do.
  If computed-in-scope turns out to matter later, that's a deliberate,
  separate follow-up to ref.lua (give ComputedRefImpl a real :stop()
  first), not something to silently paper over here.
]]

local M = {}
---@cast M Reactive.ScopeModule

-- ===========================================================================
-- module-level active-scope tracking
-- ===========================================================================

M.activeEffectScope = nil

-- ===========================================================================
-- EffectScope
-- ===========================================================================

local EffectScope = {}
---@cast EffectScope Reactive.EffectScope

EffectScope.__index = EffectScope
M.EffectScope = EffectScope

function EffectScope.new()
  local self = setmetatable({
    active = true,
    effects = {},   -- array of ReactiveEffect-shaped subscribers registered while this scope was active
    cleanups = nil, -- array of onScopeDispose() callbacks, lazily created
  }, EffectScope)
  return self
end

function EffectScope:_recordEffect(sub)
  self.effects[#self.effects + 1] = sub
end

function EffectScope:run(fn)
  if not self.active then
    return nil
  end
  local prevScope = M.activeEffectScope
  M.activeEffectScope = self
  local ok, result = pcall(fn)
  M.activeEffectScope = prevScope
  if not ok then
    error(result, 0)
  end
  return result
end

function EffectScope:stop()
  if not self.active then
    return
  end
  for _, sub in ipairs(self.effects) do
    -- Every subscriber kind THIS FILE ever registers exposes :stop()
    -- (see :_recordEffect()'s doc comment for exactly which kinds that
    -- is -- currently only ReactiveEffect, i.e. effect()/watch()/
    -- watchEffect()). computed() deliberately does NOT self-register
    -- (see this file's header) so it's never in this list -- if that
    -- ever changes, ComputedRefImpl would need a :stop() method first,
    -- since it has none today.
    sub:stop()
  end
  self.effects = {}

  if self.cleanups then
    for i = #self.cleanups, 1, -1 do
      self.cleanups[i]()
    end
    self.cleanups = nil
  end

  self.active = false
end

-- ===========================================================================
-- public effectScope() / getCurrentScope() / onScopeDispose() API
-- ===========================================================================

function M.effectScope()
  return EffectScope.new()
end

function M.getCurrentScope()
  return M.activeEffectScope
end

function M.onScopeDispose(fn, failSilently)
  local scope = M.activeEffectScope
  if scope then
    if not scope.cleanups then
      scope.cleanups = {}
    end
    scope.cleanups[#scope.cleanups + 1] = fn
  elseif not failSilently then
    error("onScopeDispose() was called when there was no active effect scope to associate with.", 2)
  end
end

return M
