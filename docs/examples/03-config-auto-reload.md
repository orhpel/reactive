# 03 — Config Auto-Reload, or "Please Stop Restarting the Server"

**Shows off:** `watch()` with `deep`, `onCleanup`  
**Difficulty:** ⭐⭐  
**Why you'd use this:** You have nested config data from a file, you want
to react to changes, and you're currently doing `while true do ... end`
with a `sleep(1)` and hoping for the best.

## The premise

You have a config file (`config.lua`) that returns a table. It changes
whenever someone on the team edits it. You want:

- On change: rebuild the *relevant subsystem* (database connection,
  logger, feature flags).
- On old subsystem teardown: close connections, flush buffers.
- No polling of unrelated fields. No restarting the whole service
  because someone bumped a debug flag.

## The classic approach (and why it hurts)

```lua
-- Don't do this.
local last_mtime = 0
local last_config = load_config()

while true do
  sleep(1)
  local mtime = get_mtime("config.lua")
  if mtime ~= last_mtime then
    last_mtime = mtime
    local new_config = load_config()
    if not deep_equal(new_config, last_config) then
      apply_config(new_config)  -- 💥 but what changed? you don't know.
      last_config = new_config
    end
  end
end
```

You get a boolean "something changed." You don't get "the `debug` flag
changed, but the database host didn't." So you re-open the database on
every edit, including when someone fixed a typo in a comment. Have fun.

## With `reactive.lua`

```lua
local reactive = require("reactive")
local _reactive = reactive.reactive
local watch     = reactive.watch

-- Load the config once, wrap it in a reactive proxy.
local config = _reactive(load_config())

-- Watch the WHOLE thing, deeply. Whenever anything anywhere inside
-- `config` changes, this fires. `onCleanup` runs before every re-run
-- (so old subsystems get torn down before new ones spin up).
watch(config, function(new_cfg, old_cfg, onCleanup)
  -- We don't know WHICH field changed — but we don't need to. We can
  -- diff the pieces we actually care about.
  if new_cfg.database ~= old_cfg.database then
    -- Careful: `new_cfg` and `old_cfg` are the SAME reactive proxy
    -- reference (see "Deep watching" in the docs). We compare the
    -- *current* value against whatever we want to rebuild.
    print("[config] database changed — reconnecting")
    local conn = connect(new_cfg.database)
    onCleanup(function()
      print("[config] tearing down old db connection")
      conn:close()
    end)
  end

  if new_cfg.logger.level ~= old_cfg.logger.level then
    print(("[config] logger level → %s"):format(new_cfg.logger.level))
    set_log_level(new_cfg.logger.level)
  end
end, { deep = true })

-- Elsewhere, the config file is re-read and pushed into the reactive
-- table. Note we only overwrite the fields that exist in the new config;
-- the reactive proxy handles the rest.
local function reload_from_disk()
  local fresh = load_config()
  for k, v in pairs(fresh) do
    config[k] = v
  end
end
```

## What's actually happening

1. `watch(config, cb, { deep = true })` sets up an effect that walks every
   nested table of `config` on every run, so any change anywhere triggers
   the callback.
2. `onCleanup` registers a teardown that fires **before the next callback
   run** — perfect for "close the old database before opening the new one."
3. When we mutate `config.database.host = "new-host"`, the deep traversal
   notices the change and fires the callback.

## The reference-identity gotcha (important)

Because `config` is a reactive proxy, `new_cfg == old_cfg` **always** —
the proxy is the same table on every read. So `if new_cfg ~= old_cfg`
will never be true.

The idiomatic pattern is:

```lua
watch(config, function(_, _, onCleanup)
  -- Re-read the fields you care about, every time. Compare against
  -- your own remembered state if you need "did this specific field
  -- change," or just unconditionally rebuild.
  rebuild_subsystem_from_current_state(config)
  onCleanup(teardown_subsystem)
end, { deep = true })
```

Or, if you want per-field change detection, use a **getter** source:

```lua
watch(
  function() return config.database end,
  function(new_db, old_db, onCleanup)
    -- `new_db` and `old_db` are the same proxy again — but the
    -- *fact that the watcher fired* means something inside it changed.
    -- So rebuild unconditionally and let onCleanup handle teardown.
    local conn = connect(config.database)
    onCleanup(function() conn:close() end)
  end,
  { deep = true }
)
```

Yes, it's a little odd. It's also exactly what Vue does, and the docs
explain why.

## When to reach for `deep = N` instead of `deep = true`

`deep = true` is "walk the entire config tree every time." For a small
config, that's fine. For a giant one (say, a game with 5000 item
definitions in a settings table), you probably want:

```lua
watch(config, cb, { deep = 2 })
-- Only descends 2 levels below `config`. So `config.database.host` is
-- watched; `config.items[5].stats.damage` is not.
```

The docs have the full spec on what `N` actually counts. Short version:
`N` = how many levels below the root you're willing to care about.

## Why this beats a file-watcher loop

- **You get structured change notifications**, not "the file mtime
  changed, diff it yourself."
- **Cleanup is atomic.** No "did I forget to close the last connection?"
  — the framework runs your cleanup before the next callback, guaranteed.
- **You can hot-patch individual fields** without diffing the whole
  config.
- **The dependency tracking is sub-field-accurate.** The watcher only
  fires if the *watched* slice of state changed; if you later narrow
  the source to `config.logger`, edits to `config.database` stop
  spamming your log callback.

## Reference

- [`reactive()`](../04-reactive-objects.md) — deep proxy for plain Lua tables
- [`watch()`](../05-watch.md) — watching a source, with `immediate`, `once`, and `deep` options
- [Deep watching](../09-deep-watching.md) — what `deep = true` vs `deep = N` actually mean, and the reference-identity caveat for reactive-proxy values
- [`onWatcherCleanup()` / `onCleanup`](../05-watch.md) — per-run cleanup callbacks

→ **Next:** [04-game-simulation-tick.md](04-game-simulation-tick.md)