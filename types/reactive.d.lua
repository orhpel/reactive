---@meta reactive

-- reactive()/shallowReactive()/readonly()/shallowReadonly() proxies.
-- Design ported from Vue 3's @vue/reactivity reactive.ts /
-- baseHandlers.ts.

---One shared metatable backs all four variants; per-instance
---readonly/shallow flags live in weak-keyed side tables in the module.
---@class Reactive.ReactiveProxy
local ReactiveProxy = {}

---Reactive trigger kinds reported to `trigger()`.
---@class Reactive.TriggerOpTypes
---@field ADD "add" A previously-absent key was assigned.
---@field DELETE "delete" A key was removed (raw[key] = nil).
---@field SET "set" An existing key was assigned a new value.

---Public surface of `reactive.reactive`.
---@class Reactive.ReactiveModule
---@field TriggerOpTypes Reactive.TriggerOpTypes
---@field ITERATE_KEY table Sentinel key used for whole-table iteration deps (read by __pairs / __len).
local M = {}

---Wraps a plain table in a reactive, deep, read/write proxy. Repeated
---calls on the same raw table return the same proxy.
---@overload fun(target: table): Reactive.ReactiveProxy
---Non-tables, already-reactive targets, and markRaw()-marked tables
---are returned unchanged.
---@overload fun(target: any): any
function M.reactive(target) end

---Like reactive(), but only the top-level table's own keys are tracked
---and lazily wrapped. Table values stored at a key are returned as-is.
---@overload fun(target: table): Reactive.ReactiveProxy
---Non-tables (and already-proxied/already-marked targets) are returned
---unchanged.
---@overload fun(target: any): any
function M.shallowReactive(target) end

---Wraps a plain table in a deep, read-only proxy. Any write (including
---into nested tables, themselves wrapped as readonly) raises an error.
---Reading through a readonly proxy does not track a dependency.
---@overload fun(target: table): Reactive.ReactiveProxy
---Non-tables (and already-proxied/already-marked targets) are returned
---unchanged.
---@overload fun(target: any): any
function M.readonly(target) end

---Combines readonly() and shallowReactive(): top-level writes error,
---but table values stored at keys are left as-is (fully mutable).
---@overload fun(target: table): Reactive.ReactiveProxy
---Non-tables (and already-proxied/already-marked targets) are returned
---unchanged.
---@overload fun(target: any): any
function M.shallowReadonly(target) end

---True for a proxy produced by any of the four variant constructors.
---@param value any
---@return boolean
function M.isReactive(value) end

---True specifically for a readonly() or shallowReadonly() proxy.
---@param value any
---@return boolean
function M.isReadonly(value) end

-- True if `value` is specifically a shallowReactive() or
-- shallowReadonly() proxy.
-- ported from reactive.ts's `isShallow()` (the reactive.lua-side one --
-- ref.lua has its own isShallow() for shallowRef(), a separate check
-- against a separate flag on a separate object shape; no collision
-- since they check different types of values, but worth noting both
-- exist)
---@param value any
---@return boolean
function M.isShallow(value) end

-- True for a reactive-family proxy of ANY variant -- alias for
-- isReactive() here (this project's isReactive() doesn't have Vue's
-- own isReactive()/isProxy() distinction -- see isReactive()'s doc
-- comment above).
---@param value any
---@return boolean
function M.isProxy(value) end

-- Returns the raw backing table of a reactive-family proxy (any
-- variant), or `value` unchanged if it isn't one.
---@param value Reactive.ReactiveProxy
---@return table
---`value` unchanged if not a reactive-family proxy.
---@overload fun(value: any): any
function M.toRaw(value) end

-- Marks a table so reactive()/shallowReactive()/readonly()/
-- shallowReadonly() never wrap it. Returns the table itself.
---@param value table
---@return table
---@overload fun(value: any): any
function M.markRaw(value) end

-- Returns a reactive proxy of `value` if it's a table, else `value`
-- unchanged. Used internally where Vue calls toReactive() (e.g.
-- ref.lua's RefImpl constructor/setter, for a non-shallow ref).
---@param value table
---@return Reactive.ReactiveProxy
---@overload fun(value: any): any
function M.toReactive(value) end

---Tracks access to `target[key]`. Creates the target's Dep map and the
---specific key's Dep on first access.
---@param target table
---@param key any
function M.track(target, key) end

--- Notifies subscribers of `target[key]`, and (for ADD/DELETE) also the
--- target's ITERATE_KEY subscribers -- effects that iterated the whole
--- table (once M.pairs()/iteration tracking exists, see "Known
--- limitations") need to re-run when a key is added or removed, not
--- just when an existing key's value changes.
---@param target table
---@param triggerType Reactive.TriggerOpType
---@param key any
function M.trigger(target, triggerType, key) end

return M