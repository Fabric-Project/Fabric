# Fabric and Satin: Performance

> Kept identical in Fabric (`PERFORMANCE.md`) and Satin (`PERFORMANCE.md`). Change both together. [PRINCIPLES.md](PRINCIPLES.md) overrides it.

Rules for code that runs every frame. Each has its reason, so you can tell when one doesn't apply. Background: Swift's [Writing High-Performance Swift Code](https://github.com/swiftlang/swift/blob/main/docs/OptimizationTips.rst), written for compiler and standard library developers: its tips trade against each other and change between compilers, so take them as tools, not rules.

## Measure

- **Measure in Release with the performance tests.** Add a sample graph when none covers the case. Don't use Debug timings to predict Release performance.
- **A faster number counts only if the same work completed.** Check the output, that every iteration ran, and that the GPU finished without errors.
- **CPU cost, GPU time and frame pacing are three results.** Report each, and measure warm-up, steady state and change-heavy runs separately.
- **Compare absolute costs and caller stacks, not runtime percentages.** A bigger share of a smaller total isn't a regression. Profile again after each change.
- **Compare builds alternately in one sitting.** Timings swing between sessions.

## Do

- **Fix the pattern, not the call site.** Overhead spread across many calls only moves when the shared pattern changes.
- **Remove repeated work before adding machinery.** One conversion and one notification per operation, before any new cache or storage.
- **Mark derived state stale on change; rebuild once, when it's next needed.** Time, camera, iteration and input change every frame even when the graph doesn't.
- **Once per frame isn't once per evaluation.** Iterator and Render to Image evaluate subgraphs repeatedly, each with its own values and GPU work.
- **Track change with integer revisions.** Bump them with wrapping arithmetic (`&+= 1`) so a long run never traps, and compare them for equality, never with `<`.
- **A revision says a cache is stale; it doesn't free what the cache holds.** Evict on the lifecycle events that already exist, descendants included.
- **Index arrays by slot.** Keep arrays of class references in `ContiguousArray`, and reuse them with `removeAll(keepingCapacity: true)`.
- **Mark classes and members `final` and `private`** unless they need to be open, so the compiler calls them directly and can prove their accesses safe. Keep deliberate extension points (open classes, plugin hooks); go concrete only where measurement says dispatch costs.
- **Keep hot mutable state together** in one struct, changed once per operation.
- **Make class-only protocols `AnyObject`.**

## Don't

- **Allocate in a warmed-up frame.** Reuse storage, and release capacity a temporary peak left behind.
- **Use dictionaries or sets where an array will do.**
- **Use `weak`, delegates or `[weak self]` on hot objects.** One weak reference gives an object a side table, and every retain and release on it then takes the slow path. Use an owner-held `unowned` link, cleared when the owner is torn down; never trade a weak reference for a retain cycle.
- **Compare strings in hot code.** If you need a choice, use an enum.
- **Call through protocols or existentials in tight loops** where measurement shows the dispatch.
- **Push changes through Combine, `@Published` or `@Observable` in the core.**
- **Add `unsafeFlags` to `Package.swift`.** SwiftPM rejects them in pinned dependencies.

## Open question

- **`@exclusivity(unchecked)`** cut CPU on the 200-iteration Model Iteration graph from 40–45% to 33–40% (Release, Satin and Fabric hot storage, `local/all-optimizations` against main). It's barely documented, and it turns a runtime overlap check into undefined behaviour. It stays an experiment: use it only with a written argument that the storage can't overlap, and weigh it against grouping hot state structurally, one measured site at a time.
