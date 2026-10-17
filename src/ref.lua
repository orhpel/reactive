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

local dep_module = require("reactive.dep")
local effect = require("reactive.effect")

local M = {}

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
    reactive_module = require("reactive.reactive")
  end
  return reactive_module
end

-- ===========================================================================
-- ref()
-- ===========================================================================

--- ported from ref.ts's `RefImpl` class
local RefImpl = {}
RefImpl.__index = RefImpl
M.RefImpl = RefImpl

-- Creates a ref wrapping `value`. If `value` is already a ref, returns
-- it unchanged (matches Vue's createRef() early-out). Table values are
-- deep-wrapped via reactive.lua's toReactive(), same as Vue's RefImpl
-- constructor calling toReactive() -- so `ref({foo=1}).value.foo = 2`
-- is itself reactive, not just the top-level `.value` assignment.
-- ported from ref.ts's `ref()` / `createRef()`
function M.ref(value)
  return M.createRef(value, false)
end

-- Creates a ref wrapping `value`, but WITHOUT deep-wrapping table
-- values via toReactive() -- `.value` itself is still tracked/
-- triggered normally (assigning a whole new value re-triggers), but
-- mutating INTO a table value (`shallowRef({}).value.foo = 1`) does
-- NOT track/trigger, because the stored value is never wrapped in a
-- reactive() proxy in the first place. Use M.triggerRef() to force a
-- manual notification after such an in-place mutation -- same pattern
-- Vue documents for shallowRef.
-- ported from ref.ts's `shallowRef()`
function M.shallowRef(value)
  return M.createRef(value, true)
end

-- Shared constructor for ref()/shallowRef() -- both just call this with
-- a different `shallow` flag, mirroring Vue's own createRef(value,
-- shallow) helper (ref.ts) rather than duplicating the ref-check +
-- setmetatable logic twice.
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
  if key == "value" then
    local reactive_mod = getReactiveModule()
    local oldValue = rawget(self, "_value")
    local rawOld = reactive_mod.toRaw(oldValue)
    local rawNew = reactive_mod.toRaw(newValue)
    if rawNew ~= rawOld then
      if rawget(self, "_shallow") then
        rawset(self, "_value", newValue)
      else
        rawset(self, "_value", reactive_mod.toReactive(newValue))
      end
      self.dep:trigger()
    end
    return
  end
  rawset(self, key, newValue)
end

-- Checks whether `r` is a ref created by M.ref(), M.shallowRef(),
-- M.computed(), or M.toRef() (either shape it can return).
-- ported from ref.ts's `isRef()`
function M.isRef(r)
  if type(r) ~= "table" then
    return false
  end
  local mt = getmetatable(r)
  return mt == RefImpl or mt == M.ComputedRefImpl or mt == M.ObjectRefImpl or mt == M.GetterRefImpl
end

--- Returns r.value if r is a ref, otherwise returns r unchanged.
--- ported from ref.ts's `unref()`
function M.unref(r)
  if M.isRef(r) then
    return r.value
  end
  return r
end

-- True if `r` is a ref created by M.shallowRef() specifically -- false
-- for a normal ref(), a computed(), an ObjectRefImpl/GetterRefImpl
-- (toRef()'s return types, neither of which has a `_shallow` field at
-- all, so this correctly falls through to `false` for them via rawget
-- returning nil), or any non-ref value.
-- ported from ref.ts's `isShallow()`
function M.isShallow(r)
  return type(r) == "table" and rawget(r, "_shallow") == true
end

--- Normalizes a ref, a plain value, or a getter function to a plain
--- value. Unlike unref(), also calls through zero-arg functions.
--- ported from ref.ts's `toValue()`
function M.toValue(source)
  if type(source) == "function" then
    return source()
  end
  return M.unref(source)
end

--- Force-triggers a ref's subscribers even if the value didn't change
--- (e.g. after mutating a table stored in a ref in place, which
--- `hasChanged` wouldn't otherwise detect since the reference itself is
--- unchanged).
--- ported from ref.ts's `triggerRef()`
function M.triggerRef(r)
  if M.isRef(r) and r.dep then
    r.dep:trigger()
  end
end

-- ===========================================================================
-- computed()
-- ===========================================================================

-- ported from computed.ts's `ComputedRefImpl` class
local ComputedRefImpl = {}
ComputedRefImpl.__index = function(self, key)
  if key == "value" then
    local link = self.dep:track()
    effect.refreshComputed(self)
    if link then
      link.version = self.dep.version
    end
    return rawget(self, "_value")
  end
  return ComputedRefImpl[key]
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

-- Called by Dep:notify() when one of this computed's own deps changes.
-- Marks the computed dirty and, unless already queued (or this IS the
-- currently-running subscriber, which would be self-recursion),
-- schedules its OWN dep to be notified too. Returning true tells the
-- calling Dep:notify() to also notify this computed's dep directly.
-- ported from computed.ts's `ComputedRefImpl:notify()`
function ComputedRefImpl:notify()
  self.flags = self.flags | effect.EffectFlags.DIRTY
  if self.flags & effect.EffectFlags.NOTIFIED == 0 and effect.activeSub ~= self then
    effect.batch(self, true)
    return true
  end
end

-- Creates a computed ref. `getterOrOptions` is either a function
-- `(oldValue) -> newValue`, or a table `{ get = fn, set = fn }` for a
-- writable computed.
-- ported from computed.ts's `computed()`
function M.computed(getterOrOptions)
  local getter, setter
  if type(getterOrOptions) == "function" then
    getter = getterOrOptions
  else
    getter = getterOrOptions.get
    setter = getterOrOptions.set
  end

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
  if key == "value" then
    local source = rawget(self, "_source")
    local sourceKey = rawget(self, "_key")
    local value = source[sourceKey]
    if value == nil then
      return rawget(self, "_defaultValue")
    end
    return value
  end
  return ObjectRefImpl[key]
end
ObjectRefImpl.__newindex = function(self, key, newValue)
  if key == "value" then
    local source = rawget(self, "_source")
    local sourceKey = rawget(self, "_key")
    source[sourceKey] = newValue
    return
  end
  rawset(self, key, newValue)
end
M.ObjectRefImpl = ObjectRefImpl

-- A readonly ref wrapping a zero-arg getter function -- `.value` calls
-- the getter fresh on every read (so tracking comes from whatever the
-- getter itself reads, exactly like a plain effect() body would),
-- writing errors (there's no setter to forward to, mirrors computed()
-- without a `set`). Simpler than Vue's GetterRefImpl, which wraps the
-- getter in an internal computed(); this project's version just calls
-- the getter directly on every access instead -- see docs/ref.lua.md
-- for why that's a deliberate simplification, not a behavioral gap.
-- ported from ref.ts's `GetterRefImpl` class
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

-- `toRef()` has three distinct shapes depending on what's passed,
-- mirroring ref.ts's own overload set (minus TS-only overload
-- resolution, which Lua has no equivalent of -- just runtime checks
-- here, in the same priority order Vue's own toRef() body uses):
--   toRef(existingRef)        -> returns it UNCHANGED (early-out)
--   toRef(getterFn)           -> M.GetterRefImpl (readonly)
--   toRef(source, key, [default]) -> M.ObjectRefImpl (linked to source[key])
--   toRef(plainValue)         -> same as M.ref(plainValue)
-- ported from ref.ts's `toRef()`
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

-- Converts a reactive() table into a plain table of ObjectRefImpls,
-- one per key present at call time (NOT itself reactive to later key
-- add/remove on `source` -- matches Vue: toRefs() snapshots the KEY
-- SET once via a single pairs() pass, only each individual ref stays
-- linked to its own key going forward). Every value in the result is
-- itself a ref, built via M.toRef(source, key) -- so an existing ref
-- stored at a key is returned as-is (see toRef()'s own early-out),
-- same as Vue.
-- ported from ref.ts's `toRefs()`
function M.toRefs(source)
  local result = {}
  for key in pairs(source) do
    result[key] = M.toRef(source, key)
  end
  return result
end

-- ===========================================================================
-- proxyRefs()
-- ===========================================================================

-- Wraps a plain table that may contain some ref-valued keys (typically
-- the return value of a "setup"-style function mixing plain values and
-- refs) in a proxy that auto-unwraps refs on read, and auto-forwards
-- writes into an existing ref's .value rather than replacing the ref
-- itself -- the same ref-forwarding behavior reactive.lua's own
-- __newindex already does for reactive() tables, applied here to a
-- PLAIN table via its own dedicated __index/__newindex pair (no
-- Dep/tracking machinery involved at all -- this is pure unwrap/
-- forward sugar, not a reactive() proxy).
--
-- If `objectWithRefs` is ALREADY a reactive() proxy, this is a no-op
-- that returns it unchanged: reactive.lua's own ReactiveProxy.__index
-- already auto-unwraps refs on read (see reactive.lua's __index), so
-- wrapping a reactive() proxy in ANOTHER unwrap layer would be
-- redundant -- matches Vue's own `isReactive(...) ? objectWithRefs :
-- new Proxy(...)` early-out in proxyRefs().
-- ported from ref.ts's `proxyRefs()`
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
