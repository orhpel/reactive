---@meta watch

-- watch() / watchEffect() / onWatcherCleanup().
-- Deliberately simplified relative to Vue's runtime-core watch.ts:
-- callbacks fire synchronously; no scheduler option, no multi-source
-- form, no debug hooks.

---Returned by watch() and watchEffect(). Callable directly to stop
---(equivalent to :stop()); also exposes pause()/resume()/stop().
---@class Reactive.WatchHandle
---Stops the watcher for good. Same as calling the handle.
---@field stop fun(self: Reactive.WatchHandle)
---Temporarily stops reacting to changes.
---@field pause fun(self: Reactive.WatchHandle)
---Resumes and catches up on anything that changed while paused.
---@field resume fun(self: Reactive.WatchHandle)

---Options table accepted by watch().
---@class Reactive.WatchOptions
---Run the callback once immediately, in addition to on future changes. `oldValue` is nil on that first call.
---@field immediate? boolean
---Automatically stop the watcher after the callback's first run.
---@field once? boolean
---Watch nested changes too. `true`/`false`, or a non-negative integer for a depth limit. When the source is a reactive() table and this option is omitted, depth is unlimited; when omitted for other sources, no descent occurs.
---@field deep? boolean|integer

---Options table accepted by watchEffect().
---@class Reactive.WatchEffectOptions
---Automatically stop after the first re-run triggered by dependencies.
---@field once? boolean

---Public surface of `reactive.watch`.
---@class Reactive.WatchModule
local M = {}

---Cleanup callback function
---@alias Reactive.CleanupFn fun(fn: function?)

---Watch callback function that is called, if the observed value changed
---@alias Reactive.WatchHandler fun(newValue: any, oldValue: any, onCleanup: Reactive.CleanupFn)

-- Watches `source` for changes, running `cb(newValue, oldValue, onCleanup)`
-- when it changes. `source` is a ref, a computed, or a zero-arg getter
-- function. `options` (optional): `immediate` (run cb once immediately,
-- with oldValue = nil), `once` (auto-stop after the first cb run).
-- Returns a WatchHandle: callable to stop, plus `.pause()`/`.resume()`/
-- `.stop()` methods (`.stop()` and calling the handle directly do the
-- same thing, matching Vue's API shape).
-- ported from watch.ts's `watch()`, heavily simplified -- see this
-- file's header comment for exactly what was cut and why.
---@param source Reactive.Ref
---@param cb Reactive.WatchHandler
---@param options Reactive.WatchOptions?
---@return Reactive.WatchHandle
---Watches a reactive() table. When `deep` is omitted this is implicitly
---fully deep (unlimited depth); an explicit `deep` value narrows that.
---@overload fun(source: Reactive.ReactiveProxy, cb: Reactive.WatchHandler, options?: Reactive.WatchOptions): Reactive.WatchHandle
---Watches a zero-arg getter. Whatever the getter reads is what gets
---tracked; a `deep` option additionally traverses the returned value.
---@overload fun(source: function, cb: Reactive.WatchHandler, options?: Reactive.WatchOptions): Reactive.WatchHandle
function M.watch(source, cb, options) end

-- Runs `fn(onCleanup)` immediately, tracking whatever reactive state it
-- reads, and re-runs it whenever any of that state changes. Unlike
-- watch(), there's no separate source/callback split, no old/new value
-- comparison -- fn itself IS the effect. Returns the same kind of
-- WatchHandle as watch().
-- ported from watch.ts's implicit "no cb" branch of watch() (Vue
-- exposes this as a distinct watchEffect() export from runtime-core,
-- not from reactivity itself -- reimplemented directly here since this
-- project has no separate runtime-core layer to house it in).
---@param fn fun(onCleanup: Reactive.CleanupFn)
---@param options Reactive.WatchEffectOptions?
---@return Reactive.WatchHandle
function M.watchEffect(fn, options) end

-- Registers a cleanup callback against `owner` (defaults to the
-- currently-running watcher). Called right before that watcher's next
-- run, or when it's stopped. failSilently: if true, do nothing (no
-- error) when there's no active watcher to attach to.
-- ported from watch.ts's `onWatcherCleanup()`
---@param cleanupFn Reactive.CleanupFn
---@param failSilently boolean?
---@param owner Reactive.ReactiveEffect? Optional explicit owner (defaults to the currently-running watcher).
function M.onWatcherCleanup(cleanupFn, failSilently, owner) end

--- Recursively reads `value` (and everything reachable from it) so that
--- effect.lua's tracking machinery notices every key touched along the
--- way -- this IS what "deep" means here, see this file's header
--- comment for the full explanation and the reactive()-source caveat.
---
--- Simpler than Vue's traverse() (no Array/Map/Set special-casing --
---- see reactive.lua's "one table type" decision): a ref is followed
--- into its .value; anything else table-shaped is walked key by key
--- via pairs() (which itself is enough to trigger reactive.lua's
--- __pairs tracking IF the table is a reactive() proxy -- a plain,
--- non-reactive Lua table just gets walked with no tracking effect,
--- same as reading a plain value does nothing for effect.lua).
--- `seen` (a table used as a set) guards against infinite recursion on
--- cyclic structures -- same purpose as Vue's `Set` parameter.
---
--- `depth`: how many levels below `value` itself still get descended
--- into. `value` itself is always read (that's depth-independent --
--- matches Vue: even `deep: 0`/`deep: false` still reads the root
--- value once, it just never DESCENDS). `depth = nil` means unlimited
--- (== `deep = true`). `depth = 0` means "read value's own keys (via
--- pairs(), which is what actually triggers reactive.lua's
--- __pairs/ITERATE_KEY tracking for a reactive() value -- see
--- reactive.lua's docs), but do NOT recurse into any of THEIR values."
--- `depth = -1` (only ever reached internally, via depth - 1 recursion
--- -- never pass this in directly) means "don't even read this value's
--- own keys," which only matters for grandchildren-and-beyond once
--- depth has been exhausted. See M.watch()'s `deep` handling below for
--- how a plain boolean/nil `deep` option maps to a depth here, and
--- docs/watch.lua.md for why the counting convention was chosen this
--- way (deliberately NOT a straight Vue port: this project's `traverse`
--- has no array/child-index distinction to make Vue's depth semantics
--- necessary in the first place, so depth was defined to align with
--- OUR own recursion instead of importing Vue's convention unchanged).
--- ported from watch.ts's `traverse()`, with a depth-limit parameter of
--- our own definition rather than Vue's
---@param value any
---@param depth integer?
---@param seen table<table, boolean>?
---@return any
function M.traverse(value, depth, seen) end

--- Normalizes the `deep` option into a depth value for traverse():
--- `nil`/`false` -> 0 (no descent, root read only)
--- `true` -> nil (unlimited depth, matches Vue's `deep: true`)
--- a non-negative number N -> N (N levels of descent below the root)
--- a negative number -> error. A negative depth has no sensible meaning
--- under this file's own counting convention (0 already means "root
--- only, no descent" -- there's no smaller unit than that to express),
--- so this is a caller mistake to report loudly rather than silently
--- clamp to 0 or otherwise guess what was meant.
--- ported loosely from watch.ts's own normalizeDeep-equivalent inline
--- logic in doWatch(), adapted for this project's own depth convention
--- (see traverse()'s doc comment above for why the convention itself
--- differs from Vue's)
---@param deep (boolean|integer)?
---@return integer?
function M.normalizeDeep(deep) end

return M