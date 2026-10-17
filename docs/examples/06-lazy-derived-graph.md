# 06 — Lazily Derived Graphs, or "Stop Recomputing the Universe"

**Shows off:** computed-on-computed chains, laziness, and why "just
recompute everything" stops scaling  
**Difficulty:** ⭐⭐⭐  
**Why you'd use this:** You have derived state that's expensive to
compute, or that chains through several stages, and you're currently
recomputing the whole thing on every read.

## The premise

You're building a query builder. Users pick:

- A **base table** (`users`, `orders`, …).
- A set of **filters** (each with a column, operator, value).
- A set of **sorts**.
- A **limit**.

You need:

- The SQL `SELECT ... FROM ... WHERE ... ORDER BY ... LIMIT ...` string.
- The **estimated cost** of the query, computed from the plan.
- A **preview** showing the first 5 rows (which requires the actual
  query).

Each of these is derived from the previous ones. Changing a filter
invalidates the SQL, the plan, the cost, and the preview — but changing
only the *limit* should invalidate the preview and the cost, not the
`WHERE` clause string.

## The "just recompute" version

```lua
-- Don't do this.
local function get_query_string()
  return build_select(query_state)  -- walks all filters every call
end

local function get_plan()
  return analyze(get_query_string())  -- runs the analyzer every call
end

local function get_cost()
  return estimate(get_plan())  -- runs the estimator every call
end

local function get_preview()
  return execute(get_query_string(), query_state.limit)
end

-- Every render, every event, every callback:
print(get_query_string())  -- rebuilds WHERE
print(get_cost())          -- rebuilds WHERE, then analyzes, then estimates
print(get_preview())       -- rebuilds WHERE, then executes
```

If you have 20 filters and the analyzer does real work, that's 60
rebuilds of `WHERE` per render. Over a 60 fps preview, that's 3600
rebuilds per second. Of the same string. That you could have cached.

## With `reactive.lua`

```lua
local reactive = require("reactive")
local _reactive = reactive.reactive
local computed  = reactive.computed

-- The raw input. Everything else derives from this.
local query_state = _reactive({
  base_table = "users",
  filters    = {},   -- { { column="age", op=">", value=18 }, ... }
  sorts      = {},   -- { { column="name", dir="asc" }, ... }
  limit      = 10,
})

-- Derived: WHERE clause. Recomputes only when filters change.
local where_clause = computed(function()
  if #query_state.filters == 0 then return "" end
  local parts = {}
  for _, f in ipairs(query_state.filters) do
    parts[#parts+1] = ("%s %s %s"):format(f.column, f.op, tostring(f.value))
  end
  return " WHERE " .. table.concat(parts, " AND ")
end)

-- Derived: ORDER BY. Independent of WHERE — reads only `sorts`.
local order_clause = computed(function()
  if #query_state.sorts == 0 then return "" end
  local parts = {}
  for _, s in ipairs(query_state.sorts) do
    parts[#parts+1] = s.column .. " " .. s.dir
  end
  return " ORDER BY " .. table.concat(parts, ", ")
end)

-- Derived: full SELECT. Depends on WHERE and ORDER BY (and limit).
local query_string = computed(function()
  return ("SELECT * FROM %s%s%s LIMIT %d"):format(
    query_state.base_table,
    where_clause.value,
    order_clause.value,
    query_state.limit
  )
end)

-- Derived: query plan. Reads only the string (and thus, transitively,
-- everything the string depends on).
local plan = computed(function()
  return analyze(query_string.value)
end)

-- Derived: cost. Reads only the plan.
local cost = computed(function()
  return estimate(plan.value)
end)

-- Derived: preview. Reads the string and the plan — but the actual
-- execution is the expensive part.
local preview = computed(function()
  return execute(query_string.value, plan.value)
end)
```

## The magic: nothing is computed until you ask

```lua
print(cost.value)     -- runs the whole chain once
print(cost.value)     -- hits the cache, runs nothing
print(preview.value)  -- reuses `plan` and `query_string`; only runs execute()

query_state.filters[#query_state.filters+1] = { column = "active", op = "=", value = true }

print(cost.value)     -- runs analyze() and estimate() again;
                      -- reuses nothing, because `where_clause` changed,
                      -- which changed `query_string`, which changed `plan`.
```

Now the interesting part:

```lua
query_state.limit = 50

print(cost.value)          -- runs analyze() again — the string changed (LIMIT clause)
print(where_clause.value)  -- hits the cache! filters didn't change.
```

And:

```lua
query_state.sorts[1] = { column = "name", dir = "desc" }

print(where_clause.value)  -- hits the cache! sorts didn't change.
print(order_clause.value)  -- recomputes.
print(query_string.value)  -- recomputes (order clause changed).
print(cost.value)          -- recomputes (string changed, plan changed).
```

## Why this matters

Every non-trivial app has a derived-state graph, whether you acknowledge
it or not. Most codebases handle it with one of:

1. **Recompute everything on every read.** Fine for small data. Kills
   you when `analyze()` is a real parser, or when `execute()` is a real
   database call.
2. **Cache at the leaf functions.** Works, but you'll forget an
   invalidation path and ship a stale-cache bug that nobody can
   reproduce.
3. **A bespoke dependency-tracking system.** That's `reactive.lua`,
   except you'll spend two months building it, three more debugging the
   cyclic cases, and one more writing docs. Ask me how I know.

The graph in this example has six derived nodes and roughly eight
edges. Everything is validated by the tracking machinery on every read,
so you can't get a stale cache even if you tried. If you add a new
derived node tomorrow, you don't have to remember to invalidate anything
— it wires itself up on first read.

## The general pattern

**Computed-on-computed is fine.** The chain can be as deep as you want.
Each level caches independently, and a change propagates one level down
at a time — recomputation is lazy, so if you never read `preview.value`,
none of the chain below it ever runs.

This is the `computed` value proposition in one sentence:
**"don't compute what you don't need, and don't recompute what hasn't
changed."** That's it. That's the whole trick.

## Reference

- [`computed()`](../03-computed.md) — lazy, cached derived values; covers computed-on-computed chaining
- [`reactive()`](../04-reactive-objects.md) — deep proxy for plain Lua tables
- [Iteration details](../11-iteration-details.md) — what `#` and `ipairs()` track (relevant because `where_clause` reacts to `#query_state.filters` and to array indices)

→ **Back to** [examples index](README.md)