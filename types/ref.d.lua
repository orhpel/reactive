---@meta ref

-- ref(), shallowRef(), computed(), toRef()/toRefs()/proxyRefs().
-- Design ported from Vue 3's @vue/reactivity ref.ts / computed.ts.

---A basic reactive ref: `.value` reads/writes go through the shared
---RefImpl metatable. Non-shallow refs deep-wrap their table values via
---reactive.toReactive(); shallow refs store the value as-is.
---@class Reactive.Ref
---@field _shallow boolean Whether this is a shallowRef (skips deep wrapping).
---@field _value any Internal storage of the wrapped value.
---@field dep Reactive.Dependency Dep tracking reads/writes of `.value`.
---@field value any The (possibly reactive-wrapped) value.

---A lazily-evaluated, cached computed ref.
---Doubles as a Subscriber (during its own getter run) and carries its
---own Dependency in `.dep` (for downstream tracking).
---@class Reactive.ComputedRef : Reactive.Subscriber
---@field _value any The cached computed result.
---@field dep Reactive.Dependency Dep on which downstream subscribers register.
---@field deps Reactive.Link? Head of this computed's dep list (deps it reads).
---@field depsTail Reactive.Link? Tail of this computed's dep list.
---@field flags integer Bitfield of EffectFlags (DIRTY/TRACKING/...).
---@field globalVersion integer Last seen dep_module.globalVersion.
---@field fn function The getter; receives the previous cached value.
---@field setter function? Setter for a writable computed, or nil.
---@field nextBatch Reactive.Link? Batching queue link.
---@field value any Read-only for a getter-only computed; writable if a setter exists
local ComputedRef = {}

-- Called by Dep:notify() when one of this computed's own deps changes.
-- Marks the computed dirty and, unless already queued (or this IS the
-- currently-running subscriber, which would be self-recursion),
-- schedules its OWN dep to be notified too. Returning true tells the
-- calling Dep:notify() to also notify this computed's dep directly.
function ComputedRef:notify() end

---A ref linked to `source[key]` (typically a reactive() proxy field).
---Reading/writing `.value` reads/writes `source[key]` directly.
---@class Reactive.ObjectRef
---@field _source table The table containing the target key.
---@field _key any The key whose value this ref proxies.
---@field _defaultValue any Returned when source[key] is nil.
---@field value any

-- A readonly ref wrapping a zero-arg getter function -- `.value` calls
-- the getter fresh on every read (so tracking comes from whatever the
-- getter itself reads, exactly like a plain effect() body would),
-- writing errors (there's no setter to forward to, mirrors computed()
-- without a `set`). Simpler than Vue's GetterRefImpl, which wraps the
-- getter in an internal computed(); this project's version just calls
-- the getter directly on every access instead -- see docs/ref.lua.md
-- for why that's a deliberate simplification, not a behavioral gap.
---@class Reactive.GetterRef
---@field _getter fun(): any
---@field value any Read-only; returns _getter().

---Public surface of `reactive.ref`.
---@class Reactive.RefModule
---@field RefImpl Reactive.Ref
---@field ComputedRefImpl Reactive.ComputedRef
---@field ObjectRefImpl Reactive.ObjectRef
---@field GetterRefImpl Reactive.GetterRef
local M = {}

-- Creates a ref wrapping `value`. If `value` is already a ref, returns
-- it unchanged (matches Vue's createRef() early-out). Table values are
-- deep-wrapped via reactive.lua's toReactive(), same as Vue's RefImpl
-- constructor calling toReactive() -- so `ref({foo=1}).value.foo = 2`
-- is itself reactive, not just the top-level `.value` assignment.
---@param value any
---@return Reactive.Ref
function M.ref(value) end

-- Creates a ref wrapping `value`, but WITHOUT deep-wrapping table
-- values via toReactive() -- `.value` itself is still tracked/
-- triggered normally (assigning a whole new value re-triggers), but
-- mutating INTO a table value (`shallowRef({}).value.foo = 1`) does
-- NOT track/trigger, because the stored value is never wrapped in a
-- reactive() proxy in the first place. Use M.triggerRef() to force a
-- manual notification after such an in-place mutation -- same pattern
-- Vue documents for shallowRef.
---@param value any
---@return Reactive.Ref
function M.shallowRef(value) end

-- Shared constructor for ref()/shallowRef() -- both just call this with
-- a different `shallow` flag, mirroring Vue's own createRef(value,
-- shallow) helper (ref.ts) rather than duplicating the ref-check +
-- setmetatable logic twice.
---@param value any
---@param shallow boolean
---@return Reactive.Ref
function M.createRef(value, shallow) end

---True if `r` is a ref created by ref(), shallowRef(), computed(), or
---toRef().
---@param r any
---@return boolean
function M.isRef(r) end

--- Returns r.value if r is a ref, otherwise returns r unchanged.
---@overload fun(r: Reactive.Ref): any
---`r` unchanged for non-ref values.
---@overload fun(r: any): any
function M.unref(r) end

-- True if `r` is a ref created by M.shallowRef() specifically -- false
-- for a normal ref(), a computed(), an ObjectRefImpl/GetterRefImpl
-- (toRef()'s return types, neither of which has a `_shallow` field at
-- all, so this correctly falls through to `false` for them via rawget
-- returning nil), or any non-ref value.
---@param r any
---@return boolean
function M.isShallow(r) end

--- Normalizes a ref, a plain value, or a getter function to a plain
--- value. Unlike unref(), also calls through zero-arg functions.
---@overload fun(source: fun(): any): any
---Returns `.value` for a ref.
---@overload fun(source: Reactive.Ref): any
---Returns any other value unchanged.
---@overload fun(source: any): any
function M.toValue(source) end

---Force-triggers a ref's subscribers even if the value didn't change
---(e.g. after in-place mutation of a table held in the ref).
---@overload fun(r: Reactive.Ref)
---No-op for anything that isn't a ref with a `.dep`.
---@overload fun(r: any)
function M.triggerRef(r) end

---Getter function that receives the old and returns the current value.
---@alias Reactive.GetterFn fun(oldValue: any): any
---Setter function that receives the new value.
---@alias Reactive.SetterFn fun(newValue: any)

---@class Reactive.ComputedOptions: table
---@field get Reactive.GetterFn
---@field set Reactive.SetterFn?

---Creates a read-only computed from a bare getter. The getter is lazy
---and cached; it re-runs only after one of its tracked deps actually
---changed. Receives the previous cached value as `oldValue`. Writing
---to `.value` raises an error.
---@param getterOrOptions Reactive.GetterFn
---@return Reactive.ComputedRef
---Creates a writable computed from a `{ get, set }` table. Reading
---`.value` calls `get`; writing calls `set` with the new value.
---@overload fun(options: Reactive.ComputedOptions): Reactive.ComputedRef
function M.computed(getterOrOptions) end


-- `toRef()` has three distinct shapes depending on what's passed,
-- mirroring ref.ts's own overload set (minus TS-only overload
-- resolution, which Lua has no equivalent of -- just runtime checks
-- here, in the same priority order Vue's own toRef() body uses):
--   toRef(existingRef)        -> returns it UNCHANGED (early-out)
--   toRef(getterFn)           -> M.GetterRefImpl (readonly)
--   toRef(source, key, [default]) -> M.ObjectRefImpl (linked to source[key])
--   toRef(plainValue)         -> same as M.ref(plainValue)
---@param source table
---@param key any
---@param defaultValue any
---@overload fun(source: Reactive.Ref): Reactive.Ref
---Wraps a zero-arg getter in a readonly GetterRef.
---@overload fun(source: fun(): any): Reactive.GetterRef
---Returns an ObjectRef linked to `source[key]` (works on reactive()
---proxies and plain tables alike). Reads the RAW value at `key` so an
---existing ref stored there is returned as-is rather than re-wrapped.
---@overload fun(source: table, key: any, defaultValue?: any): Reactive.ObjectRef
---Falls through to `ref(source)` for a plain value.
---@overload fun(source: any): Reactive.Ref
function M.toRef(source, key, defaultValue) end

--- Converts a reactive() table into a plain table of ObjectRefImpls,
--- one per key present at call time (NOT itself reactive to later key
--- add/remove on `source` <br>
--- matches Vue: toRefs() snapshots the KEY
--- SET once via a single pairs() pass, only each individual ref stays
--- linked to its own key going forward). Every value in the result is
--- itself a ref, built via M.toRef(source, key) -- so an existing ref
--- stored at a key is returned as-is (see toRef()'s own early-out),
--- same as Vue.
---@param source Reactive.ReactiveProxy Reactive table to convert
---@return table
function M.toRefs(source) end

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
---@param objectWithRefs table
---@return table
function M.proxyRefs(objectWithRefs) end

return M