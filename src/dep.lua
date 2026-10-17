--[[
  reactive/dep.lua -- dependency tracking: Dep + Link
  Version: 1 -- see VERSIONS.md (repo root) before editing this file.

  See NOTES.md (repo root) first if you haven't already. Design ported
  from Vue 3's @vue/reactivity dep.ts (Dep/Link classes only, lines
  ~14-226 of the reviewed source) -- full credit to the Vue.js team for
  the underlying linked-list tracking design. This is a rewrite, not a
  copy: no WeakMap/targetMap here (that's target-object-specific and
  lives in reactive.lua instead, see ARCHITECTURE.md), no dev-only
  debug hooks, no __DEV__ branches.

  A Dep represents one tracked "thing" (a ref's value, or a reactive
  table's single property). A Subscriber (effect or computed) that
  reads it gets linked via a Link. Deps and subscribers have a
  many-to-many relationship; each Dep<->Subscriber pair is exactly one
  Link. A Link is a node in TWO doubly linked lists at once:
    - the subscriber's list of all deps it read this run
    - the dep's list of all subscribers currently tracking it
  This lets both "what did this effect read" and "who reads this dep"
  be walked in O(subscribers) / O(deps) without any hashing/Set
  overhead, and lets an unused link (dep no longer read on a re-run) be
  unlinked from both lists in O(1) instead of O(n) scans.
]]

local M = {}

-- Incremented on every reactive change. Gives computed a fast path to
-- skip re-evaluation when nothing at all has changed since it last ran.
-- ported from dep.ts's `globalVersion`
M.globalVersion = 0

-- ===========================================================================
-- Link
-- ===========================================================================

local Link = {}
Link.__index = Link

local function newLink(sub, dep)
  return setmetatable({
    sub = sub,
    dep = dep,
    -- Before each subscriber run, all its previous links' version is
    -- reset to -1. During the run, a link's version is synced with its
    -- dep's version on access. After the run, links still at -1 (never
    -- touched this run) are unused and get cleaned up.
    version = dep.version,
    -- doubly-linked-list pointers -- nil is "no neighbour", same as
    -- undefined in the TS original
    nextDep = nil,
    prevDep = nil,
    nextSub = nil,
    prevSub = nil,
    prevActiveLink = nil,
  }, Link)
end

-- ===========================================================================
-- Dep
-- ===========================================================================

local Dep = {}
Dep.__index = Dep
M.Dep = Dep


function Dep.new(computed)
  return setmetatable({
    version = 0,
    -- link between this dep and the current active subscriber, if any
    activeLink = nil,
    -- doubly linked list of subscribing effects (tail)
    subs = nil,
    -- for object-property deps: the enclosing map + key, so an unused
    -- dep can remove itself once its subscriber count drops to zero.
    -- Set externally by reactive.lua; nil for ref/computed's own Dep.
    map = nil,
    key = nil,
    -- subscriber counter
    sc = 0,
    computed = computed,
  }, Dep)
end

--- Records that the current active subscriber (effect.activeSub) reads
--- this dep. Returns the Link, or nil if there's nothing to track
--- against (no active subscriber, tracking paused, or self-reference).
--- ported from dep.ts's `Dep:track()`
function Dep:track()
  local effect = require("reactive.effect")
  local activeSub = effect.activeSub
  if not activeSub or not effect.shouldTrack or activeSub == self.computed then
    return nil
  end

  local link = self.activeLink
  if link == nil or link.sub ~= activeSub then
    link = newLink(activeSub, self)
    self.activeLink = link

    -- append to activeSub's dep list (as new tail)
    if not activeSub.deps then
      activeSub.deps = link
      activeSub.depsTail = link
    else
      link.prevDep = activeSub.depsTail
      activeSub.depsTail.nextDep = link
      activeSub.depsTail = link
    end

    addSub(link)
  elseif link.version == -1 then
    -- reused from last run -- already a sub, just sync version
    link.version = self.version

    -- if this link isn't at the tail of activeSub's dep list, move it
    -- there, so the dep list ends up ordered by access order
    if link.nextDep then
      local nextLink = link.nextDep
      nextLink.prevDep = link.prevDep
      if link.prevDep then
        link.prevDep.nextDep = nextLink
      end

      link.prevDep = activeSub.depsTail
      link.nextDep = nil
      activeSub.depsTail.nextDep = link
      activeSub.depsTail = link

      -- link was the head -- point head to the new head
      if activeSub.deps == link then
        activeSub.deps = nextLink
      end
    end
  end

  return link
end

function Dep:trigger()
  self.version = self.version + 1
  M.globalVersion = M.globalVersion + 1
  self:notify()
end

function Dep:notify()
  local effect = require("reactive.effect")
  effect.startBatch()
  local ok, err = pcall(function()
    local link = self.subs
    while link do
      -- notify() returning true means this subscriber is a computed
      -- that needs its own dep notified too -- done here (rather than
      -- inside the computed's notify) to avoid deepening the call stack
      if link.sub:notify() then
        link.sub.dep:notify()
      end
      link = link.prevSub
    end
  end)
  effect.endBatch()
  if not ok then
    error(err, 0)
  end
end

-- ===========================================================================
-- internal helpers
-- ===========================================================================

--- Registers a link as an active subscriber of its dep (appends to the
--- dep's subscriber list). If the dep belongs to a computed that just
--- got its first subscriber, also (re)enables tracking on that computed
--- and eagerly subscribes it to all of ITS OWN deps -- this is what lets
--- a chain of computed-depending-on-computed propagate notifications
--- correctly once someone is actually listening.
--- ported from dep.ts's free function `addSub()`
function addSub(link)
  local effect = require("reactive.effect")
  local dep = link.dep
  dep.sc = dep.sc + 1

  if link.sub.flags & effect.EffectFlags.TRACKING ~= 0 then
    local computed = dep.computed
    if computed and not dep.subs then
      computed.flags = computed.flags | effect.EffectFlags.TRACKING | effect.EffectFlags.DIRTY
      local l = computed.deps
      while l do
        addSub(l)
        l = l.nextDep
      end
    end

    local currentTail = dep.subs
    if currentTail ~= link then
      link.prevSub = currentTail
      if currentTail then
        currentTail.nextSub = link
      end
    end

    dep.subs = link
  end
end

function M.removeSub(link, soft)
  local dep = link.dep
  local prevSub = link.prevSub
  local nextSub = link.nextSub

  if prevSub then
    prevSub.nextSub = nextSub
    link.prevSub = nil
  end
  if nextSub then
    nextSub.prevSub = prevSub
    link.nextSub = nil
  end

  if dep.subs == link then
    dep.subs = prevSub

    if not prevSub and dep.computed then
      local effect = require("reactive.effect")
      dep.computed.flags = dep.computed.flags & ~effect.EffectFlags.TRACKING
      local l = dep.computed.deps
      while l do
        M.removeSub(l, true)
        l = l.nextDep
      end
    end
  end

  if not soft then
    dep.sc = dep.sc - 1
    if dep.sc == 0 and dep.map then
      -- property dep has no more subscribers -- drop it from its
      -- owning map so it can be garbage collected
      dep.map[dep.key] = nil
    end
  end
end

M.Link = Link
M.newLink = newLink

return M
