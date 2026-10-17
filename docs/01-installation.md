# Installation

Good news: there isn't much to install. `reactive.lua` is a plain Lua
package with zero external dependencies — no LuaRocks, no build step,
nothing to compile.

## Requirements

- **Lua 5.4.** That's it. (If you're on an OpenComputers build, check
  that it's running a 5.4-based Lua — most modern ones are.)

## Getting it

Copy the `reactive/` folder into your project, wherever your `require`
path already looks. A typical layout:

```
your-project/
  reactive/          <- this whole folder, straight from the repo
    init.lua
    dep.lua
    effect.lua
    ref.lua
    reactive.lua
    watch.lua
    scope.lua
  main.lua
```

Then, from anywhere `your-project` is on the Lua path:

```lua
local reactive = require("reactive")
```

That single `require` is all you ever need — `reactive/init.lua` is
the one public entry point, and it pulls in everything else for you.
You never need to `require("reactive.ref")` or poke at the other files
directly (unless you're doing something advanced — see
[`reactive.internal`](reference/README.md#internal-access) in the
reference).

## Running on OpenComputers

If you're embedding this in an OpenComputers world: same deal, just
make sure the `reactive/` folder ends up somewhere your computer's
filesystem/`require` setup can see it. Nothing OpenComputers-specific
to configure beyond that — the library was written with OC's per-tick
instruction budget in mind, but that only affects how the *internals*
are written, not how you use it.

## Verifying it works

If you grabbed the repo (not just the `reactive/` folder), it ships
with a full test suite. From the repo root:

```
lua5.4 tests/run_all.lua
```

All green means you're good to go. Onward to
[`ref()` and `effect()`](02-ref-and-effect.md)!
