--[[
  reactive/reactive.lua -- reactive() via __index/__newindex proxy
  Version: 3 -- see VERSIONS.md (repo root) before editing this file.

  See NOTES.md (repo root) first if you haven't already. Design ported
  from Vue 3's @vue/reactivity reactive.ts (createReactiveObject(),
  toRaw(), isReactive(), markRaw()) and baseHandlers.ts's
  MutableReactiveHandler (get/set trap logic: lazy deep-wrapping on
  read, ADD-vs-SET trigger type, ref-unwrapping) -- full credit to the
  Vue.js team for both the overall design and the "wrap nested objects
  lazily on access instead of walking the whole tree upfront" idea in
  particular, which we keep as-is because it's a genuinely good trick,
  not just because it's what Vue does.

  Rewrite, not a copy, and deliberately narrower per Lephro's decisions
  (see ARCHITECTURE.md / PROGRESS.md):
    - ONE table type. No separate Map/Set/WeakMap/WeakSet handling
      (collectionHandlers.ts / arrayInstrumentations.ts have no Lua
      equivalent here) -- a Lua table is object and array in one.
    - __index/__newindex (property get/set) AND __pairs/__len
      (iteration, length) are tracked as of v2 -- see "Iteration
      reactivity" below.
    - No __DEV__ warnings.

  This is also where dep.ts's FREE track()/trigger() functions and its
  targetMap live (not in dep.lua -- see ARCHITECTURE.md's rationale:
  they need "what is a target" knowledge that dep.lua deliberately
  doesn't have; dep.lua only knows about a single already-constructed
  Dep, not about looking one up for an arbitrary table+key pair).

  v2: added __pairs/__len (iteration/length reactivity via the
  ITERATE_KEY dep, which existed as a sentinel since v1 but had no read
  side yet) -- built specifically to support reactive.lua/watch.lua's
  `deep` option needing to detect struct-shape changes (key add/remove),
  not value changes on an existing key (which __index/__newindex already
  covered). See "Iteration reactivity" below.

  v3: added shallowReactive()/readonly()/shallowReadonly(), per
  Lephro's explicit request (batched with a separate shallowRef() etc.
  step for ref.lua in the previous session). All four variants
  (reactive/shallowReactive/readonly/shallowReadonly) now share ONE
  ReactiveProxy metatable rather than four separate ones (Vue's own
  mutableHandlers/shallowReactiveHandlers/readonlyHandlers/
  shallowReadonlyHandlers) -- per-instance behavior is decided via two
  small weak-keyed sets (readonlySet/shallowSet) consulted by
  __index/__newindex/__pairs/__len, rather than four near-duplicate
  metatables. Deliberate simplification vs. Vue: no 4-way variant
  composition matrix (e.g. `readonly(reactive(x))` is NOT specially
  handled to produce a genuine readonly-wrapping-reactive proxy the way
  Vue's real createReactiveObject does) -- see createReactiveObject()'s
  own doc comment for the exact deviation and why it was accepted.
]]

local dep_module = require("reactive.dep")
local effect = require("reactive.effect")
local ref_module = require("reactive.ref")

local M = {}

-- ===========================================================================
-- targetMap: raw table -> { [key] = Dep }
-- ===========================================================================

-- Lua has no built-in WeakMap, but a table with weak keys
-- ({__mode = "k"}) gives the same essential property: an entry here
-- doesn't keep its raw target table alive on its own. Values (the
-- per-key Dep tables) are NOT weak -- only entries whose *raw table*
-- key becomes unreachable elsewhere should be collectible, and Lua's
-- weak-key semantics already achieve exactly that (the whole
-- raw->depsForRaw entry goes away together once raw is unreferenced).
-- ported from dep.ts's `targetMap`
local targetMap = setmetatable({}, { __mode = "k" })

-- proxy table -> raw backing table (so toRaw() is O(1))
-- Also weak-keyed for the same reason as targetMap.
local rawMap = setmetatable({}, { __mode = "k" })

-- raw table -> proxy table (so reactive(sameTable) returns the SAME
-- proxy every time, matching Vue's reactiveMap/createReactiveObject
-- early-out). FOUR separate maps, one per variant (reactive/
-- shallowReactive/readonly/shallowReadonly) -- mirrors Vue's own
-- reactiveMap/shallowReactiveMap/readonlyMap/shallowReadonlyMap: the
-- same raw table can be wrapped as more than one variant at once (e.g.
-- `readonly(reactive(x))` is a real, supported pattern in Vue), so a
-- single shared map keyed only by raw table would collide between
-- variants. Which map a given raw table's proxy lives in is chosen by
-- `(isReadonlyVariant, isShallowVariant)` -- see M.createReactiveObject().
local proxyMap = setmetatable({}, { __mode = "k" })
local shallowReactiveProxyMap = setmetatable({}, { __mode = "k" })
local readonlyProxyMap = setmetatable({}, { __mode = "k" })
local shallowReadonlyProxyMap = setmetatable({}, { __mode = "k" })

-- set of raw tables marked via markRaw() -- never wrapped
local skipSet = setmetatable({}, { __mode = "k" })

-- proxy table -> true, for proxies that are readonly/shallow variants.
-- Consulted by the single shared ReactiveProxy metatable's __index/
-- __newindex to decide behavior per-INSTANCE rather than needing four
-- separate metatables the way Vue has four separate handler objects --
-- see M.createReactiveObject()'s doc comment for why one shared
-- metatable with per-instance flags was chosen over mirroring Vue's
-- four-handlers-object structure exactly.
local readonlySet = setmetatable({}, { __mode = "k" })
local shallowSet = setmetatable({}, { __mode = "k" })

-- ===========================================================================
-- free track() / trigger() -- ported from dep.ts
-- ===========================================================================

-- Tracks access to `target[key]`. Creates the target's key->Dep map and
-- the specific key's Dep on first access.
-- ported from dep.ts's free function `track()`
local function track(target, key)
  if not (effect.shouldTrack and effect.activeSub) then
    return
  end
  local depsForTarget = targetMap[target]
  if not depsForTarget then
    depsForTarget = {}
    targetMap[target] = depsForTarget
  end
  local dep = depsForTarget[key]
  if not dep then
    dep = dep_module.Dep.new()
    dep.map = depsForTarget
    dep.key = key
    depsForTarget[key] = dep
  end
  dep:track()
end
M.track = track

-- Trigger types, mirroring constants.ts's TriggerOpTypes (subset --
-- CLEAR has no meaning without collection types).
M.TriggerOpTypes = {
  SET = "set",
  ADD = "add",
  DELETE = "delete",
}

-- Notifies subscribers of `target[key]`, and (for ADD/DELETE) also the
-- target's ITERATE_KEY subscribers -- effects that iterated the whole
-- table (once M.pairs()/iteration tracking exists, see "Known
-- limitations") need to re-run when a key is added or removed, not
-- just when an existing key's value changes.
-- ported from dep.ts's free function `trigger()`
local function trigger(target, triggerType, key)
  local depsForTarget = targetMap[target]
  if not depsForTarget then
    dep_module.globalVersion = dep_module.globalVersion + 1
    return
  end

  effect.startBatch()
  local ok, err = pcall(function()
    local dep = depsForTarget[key]
    if dep then
      dep:trigger()
    end
    if triggerType == M.TriggerOpTypes.ADD or triggerType == M.TriggerOpTypes.DELETE then
      local iterDep = depsForTarget[M.ITERATE_KEY]
      if iterDep then
        iterDep:trigger()
      end
    end
  end)
  effect.endBatch()
  if not ok then
    error(err, 0)
  end
end
M.trigger = trigger

-- Sentinel key used for "whole-table iteration" deps. Read side: both
-- __pairs and __len track() against this key (see below). Write side:
-- trigger() (above) already forwarded ADD/DELETE to it since v1.
-- ported from dep.ts's `ITERATE_KEY`
M.ITERATE_KEY = setmetatable({}, { __tostring = function() return "<reactive iterate key>" end })

-- ===========================================================================
-- reactive() / shallowReactive() / readonly() / shallowReadonly()
-- ===========================================================================

--- ONE shared metatable for all four variants, rather than Vue's four
--- separate handler objects (mutableHandlers/shallowReactiveHandlers/
--- readonlyHandlers/shallowReadonlyHandlers). Which variant a given
--- proxy instance is behaves as is decided per-call by consulting
--- `readonlySet`/`shallowSet` (declared above) for that specific proxy
--- table -- Lua metatables are cheap and per-table, so there's no
--- strong reason to build four near-identical tables the way JS's
--- Proxy handler objects (which Vue reuses across every instance of a
--- given variant) do. `isReadonly(proxyTbl)`/`isShallow(proxyTbl)`
--- below are just thin wrappers around the same two sets.
local ReactiveProxy = {}

--- Reads target[key] from the RAW backing table, tracking the access
--- (UNLESS this proxy is readonly -- see below) and lazily wrapping the
--- result (nested tables become reactive on first access, refs get
--- unwrapped) -- mirrors baseHandlers.ts's BaseReactiveHandler:get().
---
--- Readonly proxies skip track() entirely: a readonly proxy can never
--- be the SOURCE of a change (writes error, see __newindex below), so
--- an effect/watch reading through one would track a dep that can never
--- fire -- Vue's own get() only calls track() in the `!isReadonly`
--- branch, for the same reason. (The underlying raw table CAN still
--- change via some other route -- e.g. mutating it directly, or through
--- a separate non-readonly reactive() proxy over the same raw table --
--- but that's not this proxy's concern to track; whoever holds THAT
--- other reference is responsible for its own tracking.)
---
--- Shallow proxies (shallowReactive/shallowReadonly) do NOT recurse: a
--- table value is returned AS-IS, not wrapped in reactive()/readonly()
--- -- matches Vue exactly ("shallowReactive... excluding nested
--- objects"). Non-shallow variants recurse using the SAME variant
--- (reactive() wraps children as reactive(), readonly() wraps children
--- as readonly() too -- Vue's readonly is explicitly deep).
ReactiveProxy.__index = function(proxyTbl, key)
  local raw = rawMap[proxyTbl]
  local value = raw[key]
  local readonly = readonlySet[proxyTbl]
  local shallow = shallowSet[proxyTbl]

  if not readonly then
    track(raw, key)
  end

  if ref_module.isRef(value) then
    -- A shallow variant does NOT auto-unwrap a ref either -- matches
    -- Vue's shallowReactive/shallowReadonly get(): only the top-level
    -- container is "shallow," but ref-unwrapping is itself a
    -- reactivity behavior tied to the DEEP handlers specifically.
    -- Actually verified against Vue's own source structure: shallow
    -- variants use `shallowReadonlyGet`/`shallowGet`, which return the
    -- ref itself unwrapped-once same as deep -- ref unwrapping is NOT
    -- gated by shallow in Vue. Kept consistent with deep here too.
    return shallow and value or value.value
  end

  if type(value) == "table" then
    if shallow then
      return value
    elseif readonly then
      return M.readonly(value)
    else
      return M.reactive(value)
    end
  end

  return value
end

-- Writes target[key] on the RAW backing table. Readonly proxies reject
-- every write with an error -- mirrors baseHandlers.ts's
-- readonlyHandlers.set(), which is a warning in Vue (JS can't easily
-- throw from a Proxy trap without special-casing) but this project
-- prefers a hard Lua error() for the same reason computed()'s setter-
-- less write path already does (see ref.lua's GetterRefImpl): a
-- silently-ignored write is far more likely to hide a real bug than an
-- immediate, loud failure at the call site that caused it.
--
-- Otherwise, same ADD/SET trigger + ref-forwarding logic as before --
-- unaffected by shallow, since writing THIS level's own key is the
-- same operation regardless of whether nested values get wrapped.
ReactiveProxy.__newindex = function(proxyTbl, key, newValue)
  if readonlySet[proxyTbl] then
    error("Set operation on key \"" .. tostring(key) .. "\" failed: target is readonly.", 2)
  end

  local raw = rawMap[proxyTbl]
  local oldValue = raw[key]

  if ref_module.isRef(oldValue) and not ref_module.isRef(newValue) then
    oldValue.value = newValue
    return
  end

  -- unwrap a reactive newValue back to raw before storing, so the raw
  -- backing table never holds proxy tables (keeps toRaw()/identity
  -- checks simple, and avoids double-wrapping on next read)
  newValue = M.toRaw(newValue)

  local hadKey = raw[key] ~= nil
  raw[key] = newValue

  if not hadKey then
    trigger(raw, M.TriggerOpTypes.ADD, key)
  elseif newValue ~= oldValue then
    trigger(raw, M.TriggerOpTypes.SET, key)
  end
end

-- Makes `pairs(proxyTbl)` iterate the RAW table's contents (each value
-- lazily wrapped/unwrapped exactly like __index does) instead of the
-- always-empty proxy table itself, and tracks the whole-table
-- ITERATE_KEY dep so effects that iterate re-run on ADD/DELETE (an
-- existing key's VALUE changing is already covered by that key's own
-- dep from __index -- ITERATE_KEY is specifically for the key SET
-- itself changing shape). Lua 5.4 supports the __pairs metamethod for
-- exactly this purpose.
--
-- Readonly proxies skip BOTH track() calls below, same reasoning as
-- __index. Shallow proxies don't recurse into table values, same
-- reasoning as __index.
--
-- Implementation note: rather than writing a custom stateful iterator
-- closure over the raw table's keys, this builds a plain snapshot
-- table of already-lazily-wrapped [key]=value pairs and hands that to
-- the builtin `next` via `pairs()` on the snapshot -- simpler than a
-- hand-rolled `next`-compatible iterator, and correctness (not
-- iteration-during-mutation micro-perf) is what matters for this
-- project's scale. Every value goes through the SAME wrap/unwrap logic
-- as __index (ref-unwrapping, nested reactive()/readonly() wrapping,
-- shallow pass-through) so `for k, v in pairs(proxyTbl) do` sees
-- exactly what `proxyTbl[k]` would have returned.
-- ported from dep.ts's `ITERATE_KEY` concept; no direct __pairs
-- equivalent in Vue (JS Proxy's `ownKeys`/`get` traps cover this
-- automatically for `for...in`/`Object.keys()` -- Lua's __pairs is
-- this project's closest matching hook)
ReactiveProxy.__pairs = function(proxyTbl)
  local raw = rawMap[proxyTbl]
  local readonly = readonlySet[proxyTbl]
  local shallow = shallowSet[proxyTbl]

  if not readonly then
    track(raw, M.ITERATE_KEY)
  end

  local snapshot = {}
  for k, v in pairs(raw) do
    if not readonly then
      -- track each individual key too, not just ITERATE_KEY -- an
      -- effect that reads a value while iterating should ALSO re-run
      -- when just that value changes (a plain SET, not an ADD/DELETE),
      -- same as if it had read proxyTbl[k] directly via __index.
      track(raw, k)
    end
    if ref_module.isRef(v) then
      snapshot[k] = shallow and v or v.value
    elseif type(v) == "table" then
      if shallow then
        snapshot[k] = v
      elseif readonly then
        snapshot[k] = M.readonly(v)
      else
        snapshot[k] = M.reactive(v)
      end
    else
      snapshot[k] = v
    end
  end
  return next, snapshot, nil
end

-- Makes `#proxyTbl` track the ITERATE_KEY dep too (unless readonly --
-- same reasoning as __index/__pairs), then delegates to the raw
-- table's own `#` (Lua's length operator on a plain table follows its
-- own border-finding rules for tables with holes -- this project
-- doesn't second-guess that, just forwards to it). Reactive only in
-- the sense that ANY key add/remove on the table re-triggers effects
-- that read `#proxyTbl` -- same ITERATE_KEY dep __pairs uses, since
-- Lua's length is itself just "some border in the key set."
ReactiveProxy.__len = function(proxyTbl)
  local raw = rawMap[proxyTbl]
  if not readonlySet[proxyTbl] then
    track(raw, M.ITERATE_KEY)
  end
  return #raw
end

-- Shared factory behind all four public constructors below --
-- ported from reactive.ts's `createReactiveObject()`, adapted to this
-- project's single-shared-metatable design (see ReactiveProxy's own
-- doc comment above for why): `isReadonlyVariant`/`isShallowVariant`
-- pick which of the four proxyMaps to dedup against and record the
-- new proxy's flags into readonlySet/shallowSet, rather than picking
-- one of four separate handler tables the way Vue's own
-- createReactiveObject(target, isReadonly, baseHandlers, ..., proxyMap)
-- does.
--
-- Note on re-wrapping: unlike Vue, this does NOT special-case
-- "wrapping an already-reactive target in readonly() should still
-- proceed" vs. "wrapping an already-readonly target in reactive()
-- should return it as-is" -- Vue's real createReactiveObject has a
-- specific early-out for exactly one direction (readonly(reactive(x))
-- proceeds; reactive(readonly(x)) returns the readonly proxy
-- unchanged, since you can't un-readonly something). This project
-- keeps it simpler: `rawMap[target] ~= nil` (this target IS SOME
-- proxy, any variant) always short-circuits to returning `target`
-- itself unchanged, regardless of which variant is being requested.
-- Concretely: `reactive(readonly(x))` returns the readonly proxy as
-- Vue does, but so does `readonly(reactive(x))` -- which is NOT what
-- Vue does (Vue would give you a genuine readonly wrapper around the
-- reactive proxy there). Deliberate simplification: composing
-- variants this way is an edge case this project has no concrete need
-- for yet, and getting the four-way composition matrix exactly right
-- (which variant wins, in which order) is real design work with its
-- own test surface -- not worth building speculatively. If this
-- project ever needs `readonly(reactive(x))` to behave exactly like
-- Vue's, that's a deliberate, separate follow-up, not something to
-- guess at now. Passing a table that's ALREADY the exact variant being
-- requested (e.g. `reactive(someReactiveProxy)`) still works correctly
-- either way, since that's what the early-out is actually for.
local function createReactiveObject(target, isReadonlyVariant, isShallowVariant, variantProxyMap)
  if type(target) ~= "table" then
    return target
  end
  -- already ANY reactive-family proxy -- return as-is (see doc comment
  -- above for the simplification this represents vs. Vue's real
  -- 4-way composition matrix)
  if rawMap[target] ~= nil then
    return target
  end
  if skipSet[target] then
    return target
  end
  local existingProxy = variantProxyMap[target]
  if existingProxy then
    return existingProxy
  end

  local proxy = setmetatable({}, ReactiveProxy)
  rawMap[proxy] = target
  variantProxyMap[target] = proxy
  if isReadonlyVariant then
    readonlySet[proxy] = true
  end
  if isShallowVariant then
    shallowSet[proxy] = true
  end
  return proxy
end

function M.reactive(target)
  return createReactiveObject(target, false, false, proxyMap)
end

function M.shallowReactive(target)
  return createReactiveObject(target, false, true, shallowReactiveProxyMap)
end

function M.readonly(target)
  return createReactiveObject(target, true, false, readonlyProxyMap)
end

function M.shallowReadonly(target)
  return createReactiveObject(target, true, true, shallowReadonlyProxyMap)
end

function M.isReactive(value)
  return type(value) == "table" and rawMap[value] ~= nil
end

function M.isReadonly(value)
  return type(value) == "table" and readonlySet[value] == true
end

-- True if `value` is specifically a shallowReactive() or
-- shallowReadonly() proxy.
-- ported from reactive.ts's `isShallow()` (the reactive.lua-side one --
-- ref.lua has its own isShallow() for shallowRef(), a separate check
-- against a separate flag on a separate object shape; no collision
-- since they check different types of values, but worth noting both
-- exist)
function M.isShallow(value)
  return type(value) == "table" and shallowSet[value] == true
end

-- True for a reactive-family proxy of ANY variant -- alias for
-- isReactive() here (this project's isReactive() doesn't have Vue's
-- own isReactive()/isProxy() distinction -- see isReactive()'s doc
-- comment above).
-- ported from reactive.ts's `isProxy()`
M.isProxy = M.isReactive

-- Returns the raw backing table of a reactive-family proxy (any
-- variant), or `value` unchanged if it isn't one.
-- ported from reactive.ts's `toRaw()`
function M.toRaw(value)
  if type(value) == "table" and rawMap[value] ~= nil then
    return M.toRaw(rawMap[value])
  end
  return value
end

-- Marks a table so reactive()/shallowReactive()/readonly()/
-- shallowReadonly() never wrap it. Returns the table itself.
-- ported from reactive.ts's `markRaw()`
function M.markRaw(value)
  if type(value) == "table" then
    skipSet[value] = true
  end
  return value
end

-- Returns a reactive proxy of `value` if it's a table, else `value`
-- unchanged. Used internally where Vue calls toReactive() (e.g.
-- ref.lua's RefImpl constructor/setter, for a non-shallow ref).
-- ported from reactive.ts's `toReactive`
function M.toReactive(value)
  if type(value) == "table" then
    return M.reactive(value)
  end
  return value
end

return M
