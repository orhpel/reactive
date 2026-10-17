---@meta dep

-- Shared reactive-core types for dep.lua.
--
-- A Dep represents one tracked "thing" (a ref's value, or a reactive
-- table's single property). A Subscriber (effect or computed) that
-- reads it gets linked via a Link. Deps and subscribers have a
-- many-to-many relationship; each Dep<->Subscriber pair is exactly one
-- Link. A Link is a node in TWO doubly linked lists at once:
--   - the subscriber's list of all deps it read this run
--   - the dep's list of all subscribers currently tracking it

---A node connecting one subscriber to one dep. Sits in two
---doubly-linked lists simultaneously: the subscriber's dep list, and
---the dep's subscriber list.
---@class Reactive.Link
---@field dep Reactive.Dependency The dep this link connects to.
---@field sub Reactive.Subscriber The subscriber this link belongs to.
---@field version integer Version stamp, synced with dep.version on each access; reset to -1 before each run so untouched links can be cleaned up.
---@field flags integer Bitfield, reserved (see EffectFlags in effect.lua).
---@field nextBatch Reactive.Link? Next link in the batching queue (see effect.lua).
---@field prevBatch Reactive.Link? Previous link in the batching queue.
---@field nextDep Reactive.Link? Next link in the subscriber's dep list.
---@field prevDep Reactive.Link? Previous link in the subscriber's dep list.
---@field nextSub Reactive.Link? Next link in the dep's subscriber list.
---@field prevSub Reactive.Link? Previous link in the dep's subscriber list.
---@field prevActiveLink Reactive.Link? Saved dep.activeLink, restored after a run.
---@overload fun(dep: Reactive.Dependency, sub: Reactive.Subscriber): Reactive.Link
local Link = {}

---Creates a new Link between the dependency `dep` and the subscriber `sub`.
---@param sub Reactive.Subscriber
---@param dep Reactive.Dependency
---@return Reactive.Link
function Link.new(sub, dep) end

---A subscriber (effect or computed) that reads tracked deps.
---@class Reactive.Subscriber
---@field dep Reactive.Dependency? The dep this subscriber OWNS and exposes to downstream readers — the dep that other subscribers attach to when they read this subscriber's value. Present only on computed refs; nil on plain effects. NOT the same as `Reactive.Link.dep` (which is the dep a link is subscribed to).
---@field deps Reactive.Link? Head of this subscriber's list of dep links.
---@field depsTail Reactive.Link? Tail of this subscriber's list of dep links.
---@field flags integer Bitfield of EffectFlags.
---@field nextBatch Reactive.Link? Next link in the batching queue.
local Subscriber = {}

---Called by a dep when one of this subscriber's deps changes. Computeds
---return true to signal "also notify my own dep."
---@return boolean?
function Subscriber:notify() end

---One tracked "thing": a ref's value, or a reactive table's property.
---@class Reactive.Dependency : Reactive.Dep
---@field activeLink Reactive.Link? Link between this dep and the currently-running subscriber, if any.
---@field computed Reactive.ComputedRef? Owning ComputedRefImpl, if this is a computed's own dep.
---@field key any For property-deps: the key within that map.
---@field map table<any, Reactive.Dependency>? For property-deps: the enclosing key->Dep map, so an unused dep can remove itself from it.
---@field nextDep Reactive.Dependency? Next dep in the dependency's dep list.
---@field prevDep Reactive.Dependency? Previous dep in the dependency's dep list.
---@field sc integer Subscriber count.
---@field subs Reactive.Link? Doubly-linked list tail of subscribers currently tracking this dep.
---@field version integer Bumped on each trigger; links compare against it to detect staleness.
---@overload fun(computed: Reactive.ComputedRef?): Reactive.Dependency

---Dep module class table (holds `.new`).
---@class Reactive.Dep
---@field __index Reactive.Dep
---@overload fun(computed: Reactive.ComputedRef?): Reactive.Dependency
local Dep = {}

---Constructs a new Dep. Only refs/computed/reactive-properties build one
---directly (see ref.lua and reactive.lua).
---@param computed Reactive.ComputedRef? The ComputedRefImpl owning this dep, if any.
---@return Reactive.Dependency
function Dep.new(computed) end

--- Records that the current active subscriber (effect.activeSub) reads
--- this dep. Returns the Link, or nil if there's nothing to track
--- against (no active subscriber, tracking paused, or self-reference).
---@return Reactive.Link?
function Dep:track() end

---Bumps this dep's version and notifies all subscribers.
function Dep:trigger() end

---Notifies all subscribers without bumping the version (used when the
---version bump already happened elsewhere).
function Dep:notify() end

---The public surface of `reactive.dep`.
---@class Reactive.DepModule
---@field globalVersion integer Global reactive-change counter. Incremented on every reactive change; gives computed a fast path to skip re-evaluation when nothing has changed since its last run.
---@field Dep Reactive.Dep
---@field Link Reactive.Link
local M = {}

---Unlinks `link` from its dep's subscriber list. When `soft` is falsy,
---also decrements the dep's subscriber counter and drops an empty
---property-dep from its owning map.
---@param link Reactive.Link
---@param soft any
function M.removeSub(link, soft) end

return M