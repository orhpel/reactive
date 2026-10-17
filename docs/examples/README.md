# Examples

Toy counters are nice. Toy counters don't pay the bills.

This folder contains **real-world-shaped examples** — small enough to
read in one sitting, big enough to show why `reactive.lua` exists beyond
"a number that goes up." Each example uses multiple parts of the library
together and — more importantly — highlights **what would go wrong** if
you tried to build the same thing without reactive tracking.

Every example is a self-contained `.md` file with runnable Lua 5.4
snippets. They're intended to be copied, pasted, and mutated into
whatever you actually need.

## The examples

| File | Shows off |
|---|---|
| [01-reactive-counter.md](01-reactive-counter.md) | `ref()`, `computed()`, `effect()` — the hello world that isn't a hello world |
| [02-shopping-cart.md](02-shopping-cart.md) | `reactive()`, computed chains, **writable** computed |
| [03-config-auto-reload.md](03-config-auto-reload.md) | `watch()` with `deep`, `onCleanup`, and lifecycle hygiene |
| [04-game-simulation-tick.md](04-game-simulation-tick.md) | `effectScope()` for transient subsystems, `watch()` for events |
| [05-event-bus-replacement.md](05-event-bus-replacement.md) | `effect()` + scope as a *replacement* for callback soup |
| [06-lazy-derived-graph.md](06-lazy-derived-graph.md) | computed-on-computed chains, and why "just recompute everything" stops scaling |

Start with [01](01-reactive-counter.md). It's the shortest and sets up
the mental model every other example builds on.

## A note on style

These aren't production code. They're **pedagogical code** — comments are
denser than you'd write in a real project, function names are longer, and
every snippet is deliberately self-contained. That's the point. Steal the
ideas, not the formatting.
