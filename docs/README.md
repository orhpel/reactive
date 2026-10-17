# reactive.lua

A small, dependency-free reactivity system for Lua 5.4 — refs,
computed values, reactive tables, watchers, the works. If you've ever
used Vue 3 and thought "I wish I had this in Lua," well, here you go.

## Guide

Start at the top and work your way down, or jump straight to whatever
you need — every chapter stands on its own once you know what a `ref`
is.

1. [Introduction](00-introduction.md) — what this is, why it exists
2. [Installation](01-installation.md)
3. [`ref()` and `effect()`](02-ref-and-effect.md) — the two building
   blocks everything else is made of
4. [`computed()`](03-computed.md) — values derived from other values
5. [`reactive()`](04-reactive-objects.md) — whole tables, made reactive
6. [`watch()` and `watchEffect()`](05-watch.md) — reacting to change
   with more control

### Going deeper

7. [The `ref` family](06-ref-variants.md) — `shallowRef`, `toRef`,
   `toRefs`, `proxyRefs`
8. [Reactive variants](07-reactive-variants.md) — `shallowReactive`,
   `readonly`, `shallowReadonly`
9. [`effectScope()`](08-effect-scope.md) — cleaning up in bulk
10. [Deep watching](09-deep-watching.md) — the `deep` option, explained
    properly
11. [Lua stdlib interop](10-lua-interop.md) — `table.sort()` and
    friends, plus one thing to never do
12. [Iteration details](11-iteration-details.md) — `pairs()`,
    `ipairs()`, `#`, and what actually triggers what
13. [Tracking control](12-tracking-control.md) — `pauseTracking()` and
    friends, for the rare case you need them
14. [Where we differ from Vue](90-differences-from-vue.md) — for
    anyone coming from Vue with expectations

## Reference

Prefer looking things up over reading prose? The [reference](reference/)
has every public function with its exact signature and behavior, no
fluff. See [reference/README.md](reference/README.md) for how it's
organized.
