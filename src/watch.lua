--[[
  reactive/watch.lua -- watch() and watchEffect()
  Version: 3 -- see VERSIONS.md (repo root) before editing this file.

  See NOTES.md (repo root) first if you haven't already. Loosely
  inspired by Vue 3's @vue/reactivity watch.ts (the general shape:
  wrap a getter in a ReactiveEffect, use its `scheduler` to decide when
  the callback runs, compare old/new value, support cleanup via an
  onCleanup callback) -- credit to the Vue.js team for that overall
  design. This is a DELIBERATE, SUBSTANTIAL SIMPLIFICATION, not a port,
  per Lephro's own call in the very first project discussion ("bei den
  Watchern... eine einfachere Variante"). Concretely dropped, and why:

  - NO scheduler option / no runtime-core coupling. Vue's watch.ts is
    entangled with runtime-core's queuePreFlushCb/augmentJob/call
    hooks because Vue needs to batch a watcher's callback together with
    a component's render cycle. This project has no render cycle (no
    GUI framework underneath -- that's a future, separate project) and
    no async job queue. Instead: watch()/watchEffect() run their
    callback SYNCHRONOUSLY, but multiple dep changes inside one
    explicit effect.startBatch()/endBatch() pair still coalesce into a
    single callback run (via the ReactiveEffect's own dirty/scheduler
    mechanism, unchanged from effect.lua) -- see "Batching" below.
  - NO multi-source arrays (`watch({a, b}, cb)`). One source per
    watch() call. If watching several things together turns out to be
    needed later, that's an intentional follow-up, not silently
    supported today.
  - `deep` (v2) and `reactive()` sources (v2) ARE now supported --
    see "Deep watching" below for what "deep" means here concretely.
    As of v3, `deep` also accepts a NUMBER (a depth limit), not just a
    boolean -- see "Deep watching: numeric depth" below.
  - NO onTrack/onTrigger debug hooks, no WatchErrorCodes (Vue's error
    codes exist for runtime-core's error-boundary integration, not
    applicable here).

  Kept: immediate, once, onCleanup (per-run cleanup callback, via a
  lazily-created weak-keyed table mirroring watch.ts's cleanupMap),
  pause()/resume()/stop() on the returned handle.

  v2: added `deep` option + reactive()-table sources, via a
  traverse()-equivalent (walks the value, reading every nested table's
  every key so effect.lua tracks each one) plus reactive.lua's now-
  implemented __pairs/__len iteration tracking (added alongside this,
  see docs/reactive.lua.md's v2 notes) for catching key add/remove, not
  just value changes on already-known keys.

  v3: `deep` accepts a number as a depth limit, not just true/false.
  Lephro's call, made explicitly before any code was written: "an
  dieser Stelle ist mir alles recht, überlasse ich ganz deiner
  Einschätzung" -- so the counting convention below is a deliberate,
  independent design choice, NOT a straight port of Vue 3.5's
  traverse(value, depth, seen) semantics, even though it lands on
  numerically the same answer for the common cases. See "Deep
  watching: numeric depth" below for the convention and why it departs
  from Vue's own internal bookkeeping (though not from Vue's
  documented, observable `deep: N` behavior).

  ## Deep watching, concretely

  "Deep" here means: `traverse(value, depth)` (below) recursively reads
  every reachable table value once (up to `depth` levels below the
  root, or unconditionally if `depth` is nil), causing effect.lua to
  track EVERY key it touches -- refs followed into their .value,
  reactive() tables walked key by key (which ALSO tracks that table's
  ITERATE_KEY via reactive.lua's __pairs, so adding/removing a key
  re-triggers the watcher too, not just changing an existing key's
  value). This is simpler than Vue's traverse() (no Array/Map/Set
  branches needed -- see reactive.lua's own "one table type"
  simplification) but the same core idea: "just read everything (up to
  the depth budget) so the tracking machinery notices it," rather than
  a bespoke deep-equality diff.

  ## Deep watching: numeric depth (v3)

  `deep = N` (a non-negative integer) limits how many levels below the
  watched value's own keys still get descended into. Concretely, for
  `local state = reactive({ a = { b = { c = 1 } } })`:
    - `deep = 0`: state's OWN keys are read (so `state.a = ...` and key
      add/remove on `state` itself both trigger), but `state.a`'s keys
      are never read -- a change to `state.a.b` does NOT trigger.
    - `deep = 1`: state's keys AND state.a's keys are read -- a change
      to `state.a.b` (one level below state's own keys) triggers, but
      `state.a.b.c` (two levels below) does not.
    - `deep = 2`: reaches `state.a.b`'s keys too, so `state.a.b.c`
      triggers.
    - `deep = true`: unlimited (same as omitting a number, just
      explicit).
  In other words: N counts levels of descent starting from (and
  including reading, but not counting as a "descent") the root value's
  own keys. This is DELIBERATELY our own counting convention, chosen
  to align with how traverse()'s recursion already works here (each
  recursive call IS one level), rather than importing Vue's internal
  depth-decrement bookkeeping unchanged -- this project's traverse()
  has no array/child-index special-casing to make Vue's exact internal
  convention necessary in the first place. The externally observable
  behavior for a given N matches Vue's own documented `deep: N`
  semantics ("how many levels should be traversed"), so this is a
  different implementation of the same documented contract, not a
  different contract.

  IMPORTANT NON-REGRESSION: a bare `watch(reactiveTable, cb)` with NO
  `deep` option AT ALL keeps meaning "fully unlimited depth," exactly
  as it did in v2 -- introducing `deep = N` must not silently narrow
  that existing guarantee. Only an EXPLICIT `deep = <number>` (or
  `deep = false`, which normalizes to depth 0) narrows it. See
  M.watch()'s `depth` computation for exactly how `options.deep` maps
  to a traverse() depth, and tests/watch_spec.lua's "deep = N" group,
  specifically "omitting deep on a reactive() source still means fully
  unlimited depth," for the test guarding this.

  IMPORTANT CAVEAT for a `reactive()` source (or a getter returning
  one) with `deep` active (true or a number): the getter itself always
  returns the SAME proxy table reference on every run (reactive()
  dedups, see docs/reactive.lua.md), so job()'s `newValue ~= oldValue`
  reference check can NEVER see a "change" for that case on its own.
  The trigger for a deep-watched reactive() source therefore comes
  ENTIRELY from the traverse()-established deps re-triggering the
  watcher's scheduler (which re-runs the getter, which re-traverses,
  etc.) -- see M.watch()'s deep-source branch, which skips the
  value-changed check entirely in this specific case and always
  invokes cb when the scheduler fires. A ref/computed source, or a
  getter NOT returning a reactive() table, still uses the normal
  value-changed check even with `deep` active (matches Vue: `deep`
  only changes HOW MUCH gets read/tracked, not whether the old/new
  comparison itself happens for sources where that comparison is
  meaningful).
]]

local dep_module = require("reactive.dep")
local effect = require("reactive.effect")
local ref_module = require("reactive.ref")
local reactive_module = require("reactive.reactive")

local M = {}

-- ===========================================================================
-- cleanup registration (onWatcherCleanup equivalent)
-- ===========================================================================

-- effect (ReactiveEffect) -> array of cleanup functions registered
-- during that effect's most recent run. Weak-keyed so a stopped/
-- unreferenced watcher's cleanup list doesn't outlive it.
-- ported from watch.ts's `cleanupMap`
local cleanupMap = setmetatable({}, { __mode = "k" })

-- The watcher (ReactiveEffect) currently running its getter/callback,
-- or nil. Distinct from effect.lua's own `activeSub` -- a watch
-- callback runs OUTSIDE of the getter's tracked run (see M.watch()'s
-- `job` function), so onCleanup() needs its own notion of "which
-- watcher is this cleanup for" that isn't just effect.activeSub.
-- ported from watch.ts's `activeWatcher`
local activeWatcher = nil

-- Registers a cleanup callback against `owner` (defaults to the
-- currently-running watcher). Called right before that watcher's next
-- run, or when it's stopped. failSilently: if true, do nothing (no
-- error) when there's no active watcher to attach to.
-- ported from watch.ts's `onWatcherCleanup()`
function M.onWatcherCleanup(cleanupFn, failSilently, owner)
  owner = owner or activeWatcher
  if owner then
    local cleanups = cleanupMap[owner]
    if not cleanups then
      cleanups = {}
      cleanupMap[owner] = cleanups
    end
    table.insert(cleanups, cleanupFn)
  elseif not failSilently then
    error("onWatcherCleanup() was called when there was no active watcher to associate with.", 2)
  end
end

local function runCleanups(watcherEffect)
  local cleanups = cleanupMap[watcherEffect]
  if cleanups then
    cleanupMap[watcherEffect] = nil
    for _, cleanupFn in ipairs(cleanups) do
      cleanupFn()
    end
  end
end

-- Sentinel distinguishing "never run yet" from "ran once and produced
-- nil" -- Lua's nil can't tell those apart on its own, same problem
-- Vue's INITIAL_WATCHER_VALUE solves in JS (there, `undefined` has the
-- analogous ambiguity against a real undefined result).
-- ported from watch.ts's `INITIAL_WATCHER_VALUE`
local INITIAL_WATCHER_VALUE = setmetatable({}, {
  __tostring = function() return "<watch initial value sentinel>" end,
})

-- ===========================================================================
-- traverse() -- the "deep" mechanism
-- ===========================================================================

-- Recursively reads `value` (and everything reachable from it) so that
-- effect.lua's tracking machinery notices every key touched along the
-- way -- this IS what "deep" means here, see this file's header
-- comment for the full explanation and the reactive()-source caveat.
--
-- Simpler than Vue's traverse() (no Array/Map/Set special-casing --
-- see reactive.lua's "one table type" decision): a ref is followed
-- into its .value; anything else table-shaped is walked key by key
-- via pairs() (which itself is enough to trigger reactive.lua's
-- __pairs tracking IF the table is a reactive() proxy -- a plain,
-- non-reactive Lua table just gets walked with no tracking effect,
-- same as reading a plain value does nothing for effect.lua).
-- `seen` (a table used as a set) guards against infinite recursion on
-- cyclic structures -- same purpose as Vue's `Set` parameter.
--
-- `depth`: how many levels below `value` itself still get descended
-- into. `value` itself is always read (that's depth-independent --
-- matches Vue: even `deep: 0`/`deep: false` still reads the root
-- value once, it just never DESCENDS). `depth = nil` means unlimited
-- (== `deep = true`). `depth = 0` means "read value's own keys (via
-- pairs(), which is what actually triggers reactive.lua's
-- __pairs/ITERATE_KEY tracking for a reactive() value -- see
-- reactive.lua's docs), but do NOT recurse into any of THEIR values."
-- `depth = -1` (only ever reached internally, via depth - 1 recursion
-- -- never pass this in directly) means "don't even read this value's
-- own keys," which only matters for grandchildren-and-beyond once
-- depth has been exhausted. See M.watch()'s `deep` handling below for
-- how a plain boolean/nil `deep` option maps to a depth here, and
-- docs/watch.lua.md for why the counting convention was chosen this
-- way (deliberately NOT a straight Vue port: this project's `traverse`
-- has no array/child-index distinction to make Vue's depth semantics
-- necessary in the first place, so depth was defined to align with
-- OUR own recursion instead of importing Vue's convention unchanged).
-- ported from watch.ts's `traverse()`, with a depth-limit parameter of
-- our own definition rather than Vue's
local function traverse(value, depth, seen)
  if type(value) ~= "table" then
    return value
  end
  if depth ~= nil and depth < 0 then
    -- Depth budget exhausted before even reaching this value's own
    -- keys -- this only happens via the recursive call below, once
    -- depth has counted down past 0. Not a valid top-level argument.
    return value
  end
  seen = seen or {}
  if seen[value] then
    return value
  end
  seen[value] = true

  if ref_module.isRef(value) then
    -- Following a ref into its .value is not itself a "level" of
    -- descent -- a ref is a container, not a nesting step from the
    -- watched value's own point of view (matches how deepActive's
    -- non-reactive-source branch already treats a ref source: reading
    -- .value is the base read, not something `deep` gates). depth is
    -- passed through unchanged.
    traverse(value.value, depth, seen)
  else
    -- `value`'s OWN keys are always walked here (this is what actually
    -- reads them, triggering reactive.lua's per-key + ITERATE_KEY
    -- tracking for a reactive() value) -- depth only gates whether we
    -- recurse further into each key's OWN value. This is why depth = 0
    -- still does something useful for a reactive() table: it tracks
    -- that table's own keys/ITERATE_KEY, just not anything nested
    -- inside them.
    local nextDepth
    if depth ~= nil then
      nextDepth = depth - 1
    end
    for _, v in pairs(value) do
      traverse(v, nextDepth, seen)
    end
  end
  return value
end
M.traverse = traverse

-- Normalizes the `deep` option into a depth value for traverse():
-- `nil`/`false` -> 0 (no descent, root read only)
-- `true` -> nil (unlimited depth, matches Vue's `deep: true`)
-- a non-negative number N -> N (N levels of descent below the root)
-- a negative number -> error. A negative depth has no sensible meaning
-- under this file's own counting convention (0 already means "root
-- only, no descent" -- there's no smaller unit than that to express),
-- so this is a caller mistake to report loudly rather than silently
-- clamp to 0 or otherwise guess what was meant.
-- ported loosely from watch.ts's own normalizeDeep-equivalent inline
-- logic in doWatch(), adapted for this project's own depth convention
-- (see traverse()'s doc comment above for why the convention itself
-- differs from Vue's)
local function normalizeDeep(deep)
  if deep == true then
    return nil
  elseif deep == false or deep == nil then
    return 0
  elseif type(deep) == "number" and deep >= 0 then
    return deep
  else
    error("watch(): `deep` must be true, false, nil, or a non-negative number -- got " .. tostring(deep), 3)
  end
end
M.normalizeDeep = normalizeDeep

-- ===========================================================================
-- watch()
-- ===========================================================================

-- Builds the getter function for a given source. ref/computed
-- (anything M.isRef() recognizes), plain functions, and (as of v2)
-- reactive() tables are supported. Returns the getter PLUS a boolean:
-- whether this source is itself a reactive() table (needed by
-- M.watch() to pick the right change-detection strategy -- see this
-- file's header, "Deep watching" section).
local function buildGetter(source)
  if ref_module.isRef(source) then
    return function() return source.value end, false
  elseif reactive_module.isReactive(source) then
    return function() return source end, true
  elseif type(source) == "function" then
    return source, false
  else
    error(
      "watch(): invalid source -- expected a ref(), computed(), reactive() table, or a getter function. "
        .. "Multi-source arrays are not supported (see docs/watch.lua.md).",
      3
    )
  end
end

-- Watches `source` for changes, running `cb(newValue, oldValue, onCleanup)`
-- when it changes. `source` is a ref, a computed, or a zero-arg getter
-- function. `options` (optional): `immediate` (run cb once immediately,
-- with oldValue = nil), `once` (auto-stop after the first cb run).
-- Returns a WatchHandle: callable to stop, plus `.pause()`/`.resume()`/
-- `.stop()` methods (`.stop()` and calling the handle directly do the
-- same thing, matching Vue's API shape).
-- ported from watch.ts's `watch()`, heavily simplified -- see this
-- file's header comment for exactly what was cut and why.
function M.watch(source, cb, options)
  options = options or {}
  local getter, isSourceReactive = buildGetter(source)

  -- With `deep = true`/a number (or unconditionally for a reactive()
  -- source -- see this file's header, watching one without reading
  -- at least its own keys wouldn't track anything useful since the
  -- getter always returns the same proxy reference), wrap the getter
  -- so every value it reaches (up to `depth` levels below the root)
  -- gets read too, letting effect.lua's tracking machinery notice each
  -- one. ported from watch.ts's `deep`-wrapping of baseGetter.
  --
  -- `deepActive` stays a plain boolean (used below by job() to decide
  -- whether the reference-identity check is meaningful at all -- see
  -- this file's header) -- it does NOT encode depth. `depth` is the
  -- separate, actual traverse() budget:
  --   options.deep explicitly given -> normalizeDeep(options.deep)
  --     (so `deep = 0` explicitly means "root keys only")
  --   options.deep NOT given, source itself is reactive() -> unlimited
  --     depth (nil) -- this preserves the pre-existing, already
  --     documented v2 guarantee that a bare `watch(reactiveTable, cb)`
  --     is implicitly FULLY deep, not just root-level. Only an
  --     EXPLICIT `deep = 0`/a small number narrows that -- omitting
  --     `deep` entirely must not silently change behavior for anyone
  --     already relying on the v2 guarantee.
  --   neither -> deepActive is false, traverse() never runs
  local deepActive = options.deep ~= nil or isSourceReactive
  local depth
  if options.deep ~= nil then
    depth = normalizeDeep(options.deep)
  end
  -- else: depth stays nil (unlimited) for the isSourceReactive-without-
  -- explicit-deep case, and is also unused when deepActive is false.
  if deepActive then
    local baseGetter = getter
    getter = function() return traverse(baseGetter(), depth) end
  end

  local watcherEffect
  local oldValue = INITIAL_WATCHER_VALUE
  local stopped = false

  local boundOnCleanup = function(fn) M.onWatcherCleanup(fn, false, watcherEffect) end

  local function job(isImmediateFirstRun)
    if not watcherEffect or watcherEffect.flags & effect.EffectFlags.ACTIVE == 0 then
      return
    end
    if not watcherEffect:dirty() and not isImmediateFirstRun then
      return
    end

    local newValue = watcherEffect:run()
    -- A deep-watched reactive() VALUE (whether the source itself was a
    -- reactive() table, or a getter/ref that simply produces one)
    -- always yields the SAME proxy reference on every run -- see this
    -- file's header "Deep watching" section for why `newValue ~=
    -- oldValue` could never be true for that case. The scheduler
    -- firing at all (meaning: dirty() was true, meaning: some
    -- traverse()-established dep changed) IS the signal to run cb;
    -- skip the reference comparison entirely whenever deep tracking is
    -- active AND what came back is itself a reactive() proxy. Checked
    -- on the actual returned value, not just on whether the ORIGINAL
    -- source was reactive() -- a deep-watched getter function can
    -- return a reactive() table it looked up dynamically, which
    -- buildGetter() has no way to know about ahead of time (see the
    -- "getter function returning a reactive() table" test case).
    local changed = (deepActive and reactive_module.isReactive(newValue)) or (newValue ~= oldValue)
    if changed then
      runCleanups(watcherEffect)
      local previousWatcher = activeWatcher
      activeWatcher = watcherEffect
      -- NOTE: deliberately NOT the `cond and nil or x` idiom here --
      -- that idiom breaks whenever the "true" branch should itself be
      -- nil/false (`cond and nil` is always falsy, so `or x` fires
      -- unconditionally and the intended nil never comes through).
      -- Hit this exact bug while first writing this function -- see
      -- docs/watch.lua.md.
      local reportedOldValue
      if oldValue ~= INITIAL_WATCHER_VALUE then
        reportedOldValue = oldValue
      end
      local ok, err = pcall(function()
        cb(newValue, reportedOldValue, boundOnCleanup)
      end)
      activeWatcher = previousWatcher
      oldValue = newValue
      if not ok then
        error(err, 0)
      end

      if options.once then
        -- defer stop() to after this function returns rather than
        -- calling it from inside the effect's own trigger -- stopping
        -- an effect while ITS OWN scheduler/trigger call is still on
        -- the stack is unlikely to be a problem here (unlike Vue's
        -- more elaborate stop() teardown), but keeping the call site
        -- outside job() proper is cheap insurance and mirrors watch.ts
        -- wrapping cb rather than mutating job.
        watcherEffect:stop()
        stopped = true
      end
    end
  end

  watcherEffect = effect.ReactiveEffect.new(getter)
  watcherEffect.scheduler = function() job(false) end
  watcherEffect.onStop = function() runCleanups(watcherEffect) end

  if options.immediate then
    job(true)
  else
    oldValue = watcherEffect:run()
  end

  local handle
  handle = setmetatable({}, {
    __call = function()
      if not stopped then
        watcherEffect:stop()
        stopped = true
      end
    end,
    __index = {
      pause = function() watcherEffect:pause() end,
      resume = function() watcherEffect:resume() end,
      stop = function()
        if not stopped then
          watcherEffect:stop()
          stopped = true
        end
      end,
    },
  })
  return handle
end

-- ===========================================================================
-- watchEffect()
-- ===========================================================================

-- Runs `fn(onCleanup)` immediately, tracking whatever reactive state it
-- reads, and re-runs it whenever any of that state changes. Unlike
-- watch(), there's no separate source/callback split, no old/new value
-- comparison -- fn itself IS the effect. Returns the same kind of
-- WatchHandle as watch().
-- ported from watch.ts's implicit "no cb" branch of watch() (Vue
-- exposes this as a distinct watchEffect() export from runtime-core,
-- not from reactivity itself -- reimplemented directly here since this
-- project has no separate runtime-core layer to house it in).
function M.watchEffect(fn, options)
  options = options or {}
  local watcherEffect
  local stopped = false

  local boundOnCleanup = function(cleanupFn) M.onWatcherCleanup(cleanupFn, false, watcherEffect) end

  local function runWithCleanup()
    runCleanups(watcherEffect)
    local previousWatcher = activeWatcher
    activeWatcher = watcherEffect
    local ok, err = pcall(fn, boundOnCleanup)
    activeWatcher = previousWatcher
    if not ok then
      error(err, 0)
    end
  end

  watcherEffect = effect.ReactiveEffect.new(runWithCleanup)
  watcherEffect.scheduler = function()
    if watcherEffect:dirty() then
      watcherEffect:run()
      if options.once then
        watcherEffect:stop()
        stopped = true
      end
    end
  end
  watcherEffect.onStop = function() runCleanups(watcherEffect) end

  watcherEffect:run() -- initial run, always immediate (no separate "immediate" concept for watchEffect)
  if options.once and not stopped then
    watcherEffect:stop()
    stopped = true
  end

  local handle
  handle = setmetatable({}, {
    __call = function()
      if not stopped then
        watcherEffect:stop()
        stopped = true
      end
    end,
    __index = {
      pause = function() watcherEffect:pause() end,
      resume = function() watcherEffect:resume() end,
      stop = function()
        if not stopped then
          watcherEffect:stop()
          stopped = true
        end
      end,
    },
  })
  return handle
end

return M
