--[[
  reactive/ref.lua -- ref() and computed()
  Version: 3 -- see VERSIONS.md (repo root) before editing this file.

  See NOTES.md (repo root) first if you haven't already. Design ported
  from Vue 3's @vue/reactivity ref.ts (RefImpl, ref(), shallowRef(),
  isRef(), isShallow(), unref(), toRef(), toRefs(), ObjectRefImpl,
  GetterRefImpl, proxyRefs()) and computed.ts (ComputedRefImpl,
  computed()) -- full credit to the Vue.js team. Rewrite, not a copy:
  computed.ts is folded in here rather than getting its own file, per
  ARCHITECTURE.md's decision. No __DEV__ branches, no dev-only
  onTrack/onTrigger hooks, no SSR handling, no customRef yet (see
  "Not yet implemented" in docs/ref.lua.md -- ask before adding).

  v2: closed the deep-reactivity gap noted in v1 -- ref() now calls
  reactive.lua's toReactive()/toRaw() on object values, matching Vue's
  RefImpl constructor/setter. See "Deep reactivity" comment below for
  the circular-require handling this needed (reactive.lua already
  requires this file at module top level).

  v3: added shallowRef()/isShallow()/toRef()/toRefs()/proxyRefs(), per
  Lephro's explicit request to bring these four in as a batch (with
  the caveat "unless a big implementation cost" -- none of them were).
  See docs/ref.lua.md for full design notes on each, including a real
  bug caught and fixed during implementation (toRef() on a key already
  holding a ref must read the RAW value at that key via toRaw(), not
  through reactive.lua's own auto-unwrapping __index, or it would never
  recognize the existing ref and would wrongly re-wrap it).
]]

local dep_module = require("dep")
local effect = require("effect")

local M = {}
---@cast M Reactive.RefModule

-- reactive.lua requires THIS file (reactive.ref) at module top level
-- (for isRef() checks in its get/set traps), so this file cannot
-- require("reactive.reactive") at ITS top level too -- that would
-- deadlock Lua's require cache, same class of problem already solved
-- between dep.lua/effect.lua (see docs/dep.lua.md). Fix: require it
-- lazily, once, on first actual use, memoized in this upvalue -- cheap
-- (one require call total, not one per ref() call) and avoids the
-- module-load-time cycle entirely.
local reactive_module = nil
local function getReactiveModule()
  if not reactive_module then
    reactive_module = require("reactive")
  end
  return reactive_module
end

-- ===========================================================================
-- ref()
-- ===========================================================================

local RefImpl = {}
RefImpl.__index = RefImpl
M.RefImpl = RefImpl

function M.ref(value)
  return M.createRef(value, false)
end

function M.shallowRef(value)
  return M.createRef(value, true)
end

function M.createRef(value, shallow)
  if M.isRef(value) then
    return value
  end
  local storedValue
  if shallow then
    storedValue = value
  else
    storedValue = getReactiveModule().toReactive(value)
  end
  return setmetatable({
    _value = storedValue,
    _shallow = shallow or false,
    dep = dep_module.Dep.new(),
  }, RefImpl)
end

-- `.value` is implemented via __index/__newindex metamethods (fired
-- only when a key isn't found via plain rawget/rawset), so `ref.value`
-- reads/writes transparently without per-instance closures -- every
-- RefImpl instance shares the same metatable/functions.
-- ported from ref.ts's RefImpl `get value()` / `set value()`
RefImpl.__index = function(self, key)
  if key == "value" then
    self.dep:track()
    return rawget(self, "_value")
  end
  return RefImpl[key]
end

-- Compares the RAW form of both values before deciding whether the
-- value actually changed (a reactive proxy and its own raw table
-- should count as equal here) -- mirrors Vue's RefImpl setter using
-- `toRaw(this._rawValue)` on both sides via `hasChanged`. The new
-- value is stored deep-wrapped (toReactive()) UNLESS this ref is
-- shallow (`self._shallow`), in which case it's stored exactly as
-- given -- matches Vue's RefImpl setter branching on `this[ReactiveFlags.IS_SHALLOW]`.
-- Note: toRaw() on a plain (never-wrapped) value is a harmless no-op
-- (see reactive.lua's toRaw()), so the SAME comparison code below
-- works correctly for both shallow and deep refs without a separate
-- branch for the comparison itself -- only the STORAGE differs.
RefImpl.__newindex = function(self, key, newValue)
  if key ~= "value" then
    rawset(self, key, newValue)
    return
  end
  local reactive_mod = getReactiveModule()
  local oldValue = rawget(self, "_value")
  local rawOld = reactive_mod.toRaw(oldValue)
  local rawNew = reactive_mod.toRaw(newValue)
  if rawNew == rawOld then return end
  if rawget(self, "_shallow") then
    rawset(self, "_value", newValue)
  else
    rawset(self, "_value", reactive_mod.toReactive(newValue))
  end
  self.dep:trigger()
end

function M.isRef(r)
  if type(r) ~= "table" then
    return false
  end
  local mt = getmetatable(r)
  return mt == RefImpl or mt == M.ComputedRefImpl or mt == M.ObjectRefImpl or mt == M.GetterRefImpl
end

function M.unref(r)
  if M.isRef(r) then
    return r.value
  end
  return r
end

function M.isShallow(r)
  return type(r) == "table" and rawget(r, "_shallow") == true
end

function M.toValue(source)
  if type(source) == "function" then
    return source()
  end
  return M.unref(source)
end

function M.triggerRef(r)
  if M.isRef(r) and r.dep then
    r.dep:trigger()
  end
end

-- ===========================================================================
-- computed()
-- ===========================================================================

local ComputedRefImpl = {}
ComputedRefImpl.__index = function(self, key)
  if key ~= "value" then return ComputedRefImpl[key] end
  local link = self.dep:track()
  effect.refreshComputed(self)
  if link then
    link.version = self.dep.version
  end
  return rawget(self, "_value")
end
ComputedRefImpl.__newindex = function(self, key, newValue)
  if key == "value" then
    if self.setter then
      self.setter(newValue)
    else
      error("Write operation failed: computed value is readonly", 2)
    end
    return
  end
  rawset(self, key, newValue)
end
M.ComputedRefImpl = ComputedRefImpl

function ComputedRefImpl:notify()
  self.flags = self.flags | effect.EffectFlags.DIRTY
  if self.flags & effect.EffectFlags.NOTIFIED == 0 and effect.activeSub ~= self then
    effect.batch(self, true)
    return true
  end
end

function M.computed(getterOrOptions)
  local getter, setter
  if type(getterOrOptions) == "function" then
    getter = getterOrOptions
  else
    getter = getterOrOptions.get
    setter = getterOrOptions.set
  end

  ---@type Reactive.ComputedRef
  local c = setmetatable({
    _value = nil,
    dep = nil, -- set below, needs `c` itself for Dep.new(computed)
    deps = nil,
    depsTail = nil,
    flags = effect.EffectFlags.DIRTY,
    globalVersion = dep_module.globalVersion - 1,
    fn = getter,
    setter = setter,
    nextBatch = nil,
  }, ComputedRefImpl)
  c.dep = dep_module.Dep.new(c)

  return c
end

-- ===========================================================================
-- toRef() / toRefs() / ObjectRefImpl / GetterRefImpl
-- ===========================================================================

-- A ref that doesn't own a value at all -- it's a thin window onto
-- `source[key]` (typically a reactive() proxy's field, but works for
-- any table). Reading/writing `.value` reads/writes `source[key]`
-- directly, so it stays "linked": `objRef.value = x` is
-- indistinguishable from `source[key] = x`, and vice versa. No `dep`
-- of its own -- tracking/triggering is entirely delegated to
-- `source`'s own metamethods (if `source` is a reactive() proxy;
-- see the "toRef() on a non-reactive table" note in docs/ref.lua.md
-- for what happens when it isn't).
-- ported from ref.ts's `ObjectRefImpl` class
local ObjectRefImpl = {}
ObjectRefImpl.__index = function(self, key)
  if key ~= "value" then return ObjectRefImpl[key] end
  local value = rawget(self, "_source")[rawget(self, "_key")]
  if value == nil then
    return rawget(self, "_defaultValue")
  end
  return value
end
ObjectRefImpl.__newindex = function(self, key, newValue)
  if key ~= "value" then rawset(self, key, newValue) return end
  rawget(self, "_source")[rawget(self, "_key")] = newValue
end
M.ObjectRefImpl = ObjectRefImpl


local GetterRefImpl = {}
GetterRefImpl.__index = function(self, key)
  if key == "value" then
    return rawget(self, "_getter")()
  end
  return GetterRefImpl[key]
end
GetterRefImpl.__newindex = function(self, key, newValue)
  if key == "value" then
    error("Write operation failed: computed value is readonly", 2)
  end
  rawset(self, key, newValue)
end
M.GetterRefImpl = GetterRefImpl

function M.toRef(source, key, defaultValue)
  if M.isRef(source) then
    return source
  elseif type(source) == "function" then
    return setmetatable({ _getter = source }, GetterRefImpl)
  elseif key ~= nil then
    -- Read the RAW value at `key`, not through `source`'s own
    -- __index (which, if `source` is a reactive() proxy, would
    -- auto-unwrap an existing ref stored there into its .value --
    -- see reactive.lua's ReactiveProxy.__index. That auto-unwrap is
    -- exactly right for ordinary reads, but here we specifically need
    -- to know whether the STORED value is itself a ref, so we have to
    -- look underneath it). toRaw() on a plain (non-reactive) `source`
    -- is a no-op, so this works identically whether `source` is a
    -- reactive() proxy or an ordinary table.
    local existing = getReactiveModule().toRaw(source)[key]
    if M.isRef(existing) then
      return existing
    end
    return setmetatable({
      _source = source,
      _key = key,
      _defaultValue = defaultValue,
    }, ObjectRefImpl)
  else
    return M.ref(source)
  end
end

function M.toRefs(source)
  local toRef = M.toRef
  local result = {}
  for key in pairs(source) do
    result[key] = toRef(source, key)
  end
  return result
end

-- ===========================================================================
-- proxyRefs()
-- ===========================================================================

local ProxyRefsHandlers = {}
ProxyRefsHandlers.__index = function(self, key)
  local target = rawget(self, "_target")
  return M.unref(target[key])
end
ProxyRefsHandlers.__newindex = function(self, key, newValue)
  local target = rawget(self, "_target")
  local oldValue = target[key]
  if M.isRef(oldValue) and not M.isRef(newValue) then
    oldValue.value = newValue
  else
    target[key] = newValue
  end
end

function M.proxyRefs(objectWithRefs)
  if getReactiveModule().isReactive(objectWithRefs) then
    return objectWithRefs
  end
  return setmetatable({ _target = objectWithRefs }, ProxyRefsHandlers)
end

return M
