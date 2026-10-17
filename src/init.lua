--[[
  reactive/init.lua -- public API entry point
  Version: 5 -- see VERSIONS.md (repo root) before editing this file.

  See NOTES.md (repo root) first if you haven't already. This is the
  ONLY file client code should `require` (`require("reactive")`); it
  wires together dep.lua/effect.lua/ref.lua/reactive.lua/watch.lua/
  scope.lua and exposes their public functions under one flat
  namespace, e.g. `reactive.ref(0)`, `reactive.computed(fn)`,
  `reactive.reactive({})`, `reactive.effectScope()`.

  Not a Vue file port -- Vue's own index.ts plays a similar "public
  barrel export" role, but the actual list of what's exposed here is
  this project's own choice (a narrower surface, matching what's
  actually implemented -- see ARCHITECTURE.md for what's deliberately
  left out).
]]

local dep_module = require("reactive.dep")
local effect = require("reactive.effect")
local ref_module = require("reactive.ref")
local reactive_module = require("reactive.reactive")
local watch_module = require("reactive.watch")
local scope_module = require("reactive.scope")

local M = {}

-- ref.lua
M.ref = ref_module.ref
M.shallowRef = ref_module.shallowRef
M.computed = ref_module.computed
M.isRef = ref_module.isRef
M.unref = ref_module.unref
M.toValue = ref_module.toValue
M.triggerRef = ref_module.triggerRef
M.toRef = ref_module.toRef
M.toRefs = ref_module.toRefs
M.proxyRefs = ref_module.proxyRefs

-- effect.lua
M.effect = effect.effect
M.stop = effect.stop
M.onEffectCleanup = effect.onEffectCleanup
M.pauseTracking = effect.pauseTracking
M.enableTracking = effect.enableTracking
M.resetTracking = effect.resetTracking

-- reactive.lua
M.reactive = reactive_module.reactive
M.shallowReactive = reactive_module.shallowReactive
M.readonly = reactive_module.readonly
M.shallowReadonly = reactive_module.shallowReadonly
M.isReactive = reactive_module.isReactive
M.isReadonly = reactive_module.isReadonly
M.isProxy = reactive_module.isProxy
M.toRaw = reactive_module.toRaw
M.markRaw = reactive_module.markRaw
M.toReactive = reactive_module.toReactive

-- watch.lua
M.watch = watch_module.watch
M.watchEffect = watch_module.watchEffect
M.onWatcherCleanup = watch_module.onWatcherCleanup

-- scope.lua
M.effectScope = scope_module.effectScope
M.getCurrentScope = scope_module.getCurrentScope
M.onScopeDispose = scope_module.onScopeDispose

-- Combined isShallow(): ref.lua's isShallow() (shallowRef()) and
-- reactive.lua's isShallow() (shallowReactive()/shallowReadonly())
-- check two structurally different object shapes (a RefImpl-family
-- table vs. a reactive-proxy-family table) using two different
-- internal flag stores -- unlike Vue, where a single internal
-- `__v_isShallow` flag lives on both shapes uniformly, so Vue's
-- isShallow() is one check. Here, delegate to whichever module's
-- check actually applies: ref.lua's isRef() and reactive.lua's
-- isProxy() are mutually exclusive (nothing is both), so trying each
-- in turn is safe and correct, not just "probably fine" -- see
-- docs/ref.lua.md / docs/reactive.lua.md for each half's own detail.
function M.isShallow(value)
  if ref_module.isRef(value) then
    return ref_module.isShallow(value)
  end
  return reactive_module.isShallow(value)
end

-- Exposed for advanced use (building new subscriber kinds, tests, or
-- reactive.lua-adjacent tooling) -- not part of the "everyday" API
-- surface above, but deliberately not hidden either.
M.internal = {
  dep = dep_module,
  effect = effect,
  ref = ref_module,
  reactive = reactive_module,
  watch = watch_module,
  scope = scope_module,
}

return M
