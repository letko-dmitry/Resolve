# Shrinking the binary of apps that use Resolve

Optimization run `shrink-consumer-binary`, 30 October 2026, branch `optimize/shrink-consumer-binary`
(e5ad49d → 5e22824). Toolchain: Swift 6.4.2, Xcode 27.2, Apple M4.

## Result

Measured on a benchmark app that uses Resolve the way an app does: three `@Resolvable` containers with 100
registrations and 8 performables, every registration returning a type of its own (classes, `any Protocol`
existentials, small structs), built with `swift build -c release` (`-O`, whole-module, Swift 6 mode, macOS 14 target,
`-dead_strip`). The metric is the sum of all section sizes of the executable. Original and final revision measured as
one pairing, under the same conditions:

| | e5ad49d | 5e22824 | Change |
|---|---|---|---|
| Benchmark app, all sections | 417 314 B | 306 577 B | −110 737 B (−26.5%) |
| Benchmark app, stripped file | 461 432 B | 360 136 B | −101 296 B (−22.0%) |
| — the app's own module (generated code, specializations) | 353 238 B | 255 522 B | −97 716 B (−27.7%) |
| — Resolve's own code in the app | 33 332 B | 23 282 B | −10 050 B (−30.2%) |
| Holdout app (4 containers, 110 registrations, other mix), all sections | 475 905 B | 343 540 B | −132 365 B (−27.8%) |

Speed was a guard, not the goal: instructions per operation could not grow by more than 5% against the original
code. Both got cheaper (one-thread cooperative pool, median of three processes):

| | e5ad49d | 5e22824 | Change |
|---|---|---|---|
| Read of a resolved registration (`await resolver.x`) | 387.8 | 324.1 | −16.4% (holdout −19.0%) |
| `resolve()` of the whole graph, fresh resolvers | 796 516 | 778 569 | −2.3% (holdout −3.8%) |

`swift test`, SwiftLint `--strict` and SwiftFormat `--lint` pass on the final revision.

## What changed and what each change was worth

Each change was measured against the revision before it on both apps and kept only if both shrank by at least 1 KB
with both speed guards passing. The steps are not additive percentages; the total above is the original-to-final
measurement.

| Commit | Change | Forecast | Benchmark | Holdout |
|---|---|---|---|---|
| d315d73 | `value()` awaits its task once: `Resolution.task(Task, keep:)` instead of `.task` / `.keep`, so every specialization has one resume funclet (and unwind entry) less | −15…−30 KB | −18 624 B | −21 676 B |
| be98a88 | Registration factories are `@concurrent`: the factory closure no longer hops back to its caller's executor, and its type can be built from a mangled name on runtimes before Swift 6.2 instead of needing metadata accessors per registration | −5…−12 KB, sign unknown | −20 754 B | −27 608 B |
| 75d4cb4 | `Registrations` is generated as a `final class`; `Registrar.Storage` holds the instances directly, without `Box`, so containers no longer get value witnesses for the struct | −6…−10 KB | −5 280 B | −9 411 B |
| c2e4209 | The macro routes literal cache scopes: `_registrar.local.x` / `_registrar.global.x`; only a non-literal `options:` expression keeps the run-time `once` select. Every call site also lost the retain/release of the lock | −9…−22 KB | −29 760 B | −30 440 B |
| 9961c90 | Lazy types are no longer emitted into apps that do not use them: `@export(implementation)` instead of `@inlinable`, one shared `LazyState` for `Lazy` / `LazyThrowable`, and the async lazy classes' public `init` is a convenience init over a private one | −3…−6 KB | −9 774 B | −9 886 B |
| 801a627 | `LazyAsyncState.start` / `resolution` switch over `consume self`, so the per-type lock bodies stop copying the whole state; the existential ones then became identical and the compiler merged them | −4…−10 KB | −15 020 B | −21 564 B |
| 5e22824 | Tasks are awaited through one caller-isolated helper, `Resolution.value(of:)`, so the hop back after the `@concurrent` `Task.value` lives in Resolve once instead of in every specialization. Costs +2.2% instructions per `resolve()` and +0.9% per read | −3…−6 KB | −11 525 B | −11 780 B |

Rejected: making `Registration.init` non-inlinable shrank the benchmark by 7.3 KB but made `resolve()` cost 31.5% more
instructions than the original code (metadata instantiated at run time, ~2 400 instructions per registration per
`Resolver`).

## Things to keep in mind

- **Generated code reads differently.** Accesses are now `_registrar.local.database.value(self)` and
  `_registrar.global.featureFlags.value(self)`. A non-literal `options:` keeps `_registrar.database`, and a
  registration named `local` or `global` with a non-literal `options:` is reached as `_registrar[dynamicMember: \.local]`.
- **First underscored attribute in the code base.** `Resolution.value(of:)` carries
  `@_semantics("optimize.no.crossmodule")`: without it, default cross-module optimization inlines the helper back
  into the app and undoes the commit. The supported alternative is a `public` `@export(interface)` helper on a public
  type, at the cost of public API surface.
- **`LazyAsyncState.start`** now ends with a catch-all `case let state: self = state` instead of listing the cases.
- **Binary interface.** `LazyAsync` / `LazyAsyncThrowable` expose a convenience `init(_:)`, and `Registration` /
  `RegistrationThrowable` take `@concurrent` factories. Source-compatible; only matters if Resolve is ever built with
  library evolution. `Registrar.Storage` is not source-compatible: it now requires `Registrations` to be a class
  (`AnyObject & Sendable`, was `Sendable`), exposes `local` and `global` publicly, and its `init` takes a closure that
  makes the registrations (`Storage { Registrations() }`) instead of an instance. Generated code is unaffected, but a
  hand-written or vendored `Storage` built the old way stops compiling. Its documentation says not to create one by
  hand: like `Registration` and `RegistrationThrowable`, it serves generated code and sits outside the 1.x SemVer
  surface, as `Registrar` did in 1.3.2 and 1.4.0, so the release is 1.5.0.
- **README.** One sentence was wrong before this run and is corrected: the `options:` expression is evaluated each
  time a `Resolver` is created, not on every access.

## Found along the way

- Fixed in a follow-up commit, not part of the run: the first `Resolver` of a container type supplied the process-wide
  registrations, so its `.default` registrations, and the values they cache, lived as long as the process, while the
  documentation says they are discarded with their `Resolver`. This predates the run. The process-wide registrations
  are now an instance of their own.
- `LazyAsync` / `LazyAsyncThrowable` factories are still caller-isolated, which costs apps that use them per-type
  metadata accessors on deployment targets below the Swift 6.2 runtime, the same cost be98a88 removed for
  registrations. The benchmark does not use these types, so this run could not measure it.

## How far the evidence goes

- Byte counts are exact and repeatable. Instruction counts vary by 0.2–1% between runs; wall-clock time was not
  usable during the run (load average up to ~500 from simulators and builds), so contention effects are not measured.
- One consumer configuration was measured: macOS 14 deployment target, Swift 6 language mode without approachable
  concurrency, `-O`. The be98a88 metadata-accessor saving applies to deployment targets below the Swift 6.2 runtime
  (iOS 17 / macOS 14 / watchOS 10 are); the hop-back savings apply everywhere. iOS builds, `-Osize`, and
  MainActor-default modules were not measured.
- The graph is synthetic: empty types and trivial factories make Resolve's share of the binary larger than in a real
  app, while the per-registration savings carry over.
- A differently shaped holdout app confirmed every kept change and the final result.

## What is left

The app module still spends about 2.4 KB per registration, most of it outside Resolve's control: each `await` call
site costs ~180 bytes of async calling convention, `__eh_frame` holds 24.7 KB of DWARF unwind entries for async
funclets, each container's `Resolved` has ~4 KB of value witnesses, and the app's own types carry their metadata. The
remaining ideas were set aside: synchronous closures for synchronous factories, moving the factory out of the state's
generic parameters, and a second registration type for run-time options each net about 1–2 KB after the fixed cost
of a new type or extra registers at every read; awaiting all of `resolve()` in one generic call needs the same run-time
metadata that sank the non-inlinable `init`.

## Run

Eight experiments in about 2 h 40 min: seven kept, one rejected by the speed guard. Stopped because no hypothesis with a
credible net gain was left. Experiments were implemented by subagents (about 1.6 M tokens reported by the host; no
dollar figure available). The experiment log stays local in
`.context/compound-engineering/ce-optimize/shrink-consumer-binary/experiment-log.yaml`.
