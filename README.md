# Resolve

<p align="left">
<img src="https://img.shields.io/badge/Swift-6.3%2B-F05138?logo=swift&logoColor=white" alt="Swift 6.3+">
<img src="https://img.shields.io/badge/Platforms-macOS%2014%2C%20iOS%2017%2C%20watchOS%2010-lightgrey" alt="Platforms">
<img src="https://img.shields.io/badge/License-MIT-blue" alt="MIT License">
</p>

A macro-based dependency injection framework for Swift. Declare your dependencies as plain methods, and Resolve generates a thread-safe, concurrent resolver at compile time.

> **Compile-time generation** · **Per-resolver or process lifetime** · **Modular composition** · **Sendable by default** · **No runtime dependencies**

```swift
import Resolve

@Resolvable
struct AppContainer {
    @Register
    func logger() -> Logger {
        Logger(subsystem: "com.app", category: "main")
    }

    @Register
    func database(_ resolver: Resolver) async throws -> Database {
        try await Database(logger: resolver.logger)
    }

    @Perform
    func analytics(_ resolver: Resolver) async {
        await Analytics.configure(logger: resolver.logger)
    }
}

let resolver = AppContainer.Resolver(.init())
let resolved = try await resolver.resolve()

resolved.database // ready to use
```

## Requirements

| Swift | Platforms                                 |
|-------|-------------------------------------------|
| 6.3+  | macOS 14.0+, iOS 17.0+, watchOS 10.0+     |

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/letko-dmitry/Resolve.git", from: "1.1.1")
]
```

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Resolve", package: "Resolve")
    ]
)
```

## How It Works

The `@Resolvable` macro generates two nested types from your container:

- **`Resolver`** -- a facade that exposes each `@Register` as an async property and each `@Perform` as an async method. Calling `resolve()` builds the entire dependency graph.
- **`Resolved`** -- an immutable, `Sendable` aggregate holding all resolved dependencies. This is what you pass around your app. A `@Keep` registration is in there too, as a `private` property: held for as long as you hold `Resolved`, readable by nobody.

All non-transient registrations start concurrently via `async let`. All `@Perform` steps run in parallel inside a task group. Dependencies that reference siblings through `Resolver` naturally await each other, forming an implicit DAG -- and a cycle among them is rejected at compile time rather than deadlocking at runtime.

Every dependency is built **at most once per `Resolver`**. Concurrent callers share a single in-flight `Task`, so a value referenced by five siblings is still constructed once.

## Macros

### @Resolvable

Attach to a `struct` or a `class`. Any other declaration -- an `extension`, an `enum`, an `actor`, a `protocol` -- is rejected with a diagnostic.

Only functions declared **directly in the body** of the annotated type are inspected. A `@Register` placed in an extension or inside a nested type expands to nothing, and the macro warns at the attribute so you find out at build time. A member wrapped in `#if` is skipped silently -- put the conditional inside the factory body instead.

`Resolved` and `Resolver` repeat the access level of the container, so a `public` container produces types other modules can name. A `public` container must also be explicitly `Sendable`: public types get no implicit conformance, and `Resolver` stores one.

The parameter `sort` controls the order in which registrations are emitted:

```swift
@Resolvable(sort: false)     // declaration order; the default is alphabetical
struct Services { … }
```

Sorting is by the **registration** name -- the `name:` override when present, otherwise the function name. It only decides the order of the properties on `Resolved`, and with it the order of that type's memberwise initialiser. Nothing about what is built, or when, changes.

### @Register

Marks a method as a dependency factory. The return value is cached and exposed on `Resolved`.

Methods may be synchronous, `async`, `throws`, or `async throws`. They may take zero parameters or a single `Resolver` parameter to pull sibling dependencies.

A factory must be an instance method with a concrete return type. `static`, `class`, `mutating`, generic and opaque-returning (`-> some P`) methods are rejected: the return type has to work as a stored property on `Resolved`, and the factory has to be callable on an instance.

```swift
@Resolvable
struct Services {
    // Synchronous, no dependencies.
    @Register
    func featureFlags() -> FeatureFlags {
        FeatureFlags()
    }

    // Throwing, used by siblings.
    @Register
    func exerciseBundle() throws -> ExerciseBundle {
        try ExerciseBundleReader().read()
    }

    // Depends on a sibling via Resolver. Every generated getter is `async`, and
    // this one reads a throwing sibling, so the factory must be `async throws`.
    @Register
    func exerciseDataSource(_ resolver: Resolver) async throws -> ExerciseDataSource {
        try await ExerciseDataSource(bundle: resolver.exerciseBundle)
    }

    // Async, no throws.
    @Register
    func watchController() async -> WatchController {
        let controller = WatchController()
        await controller.activate()

        return controller
    }

    // Async + throwing.
    @Register
    func database() async throws -> Database {
        try await Database.open(path: "app.db")
    }

    // Async + throwing, depends on siblings via Resolver.
    @Register
    func exerciseLibrary(_ resolver: Resolver) async throws -> ExerciseLibrary {
        try await ExerciseLibrary(
            database: resolver.database,
            source: resolver.exerciseDataSource
        )
    }

    // Process-lifetime singleton -- created once, survives Resolver recreation.
    @Register(options: .once)
    func remoteConfiguration() async -> RemoteConfiguration {
        await RemoteConfiguration.fetch()
    }
}
```

> **Reading a sibling always needs `await`.** Every generated getter is `async`, whatever the factory behind it looks like. A factory that touches `resolver.somethingElse` is therefore `async` too, and `async throws` if the sibling throws.

#### Renaming a registration

`name:` decouples the exposed name from the factory's name. It renames the property on both `Resolved` and `Resolver`, and it becomes the cache key:

```swift
@Register(name: "pipeline")
func makePipeline(_ resolver: Resolver) async -> Pipeline {
    await Pipeline(database: resolver.database)
}

resolved.pipeline // not `resolved.makePipeline`
```

The value must be a **string literal** and a legal Swift identifier -- it is spliced into a property declaration. `@Register(name: someConstant)` is ignored with a warning; `@Register(name: "foo bar")` is an error.

### @RegisterTransient

Same as `@Register`, but the value is **not** included in `Resolved`. Use for intermediate wiring -- child resolvers, builders, or helpers needed only during graph construction. Still cached and callable on `Resolver`.

```swift
@Resolvable
struct WiringAssembly {
    let essential: Essential

    // Synchronous transient -- cheap to build, used by siblings.
    @RegisterTransient
    func thirdPartyResolver() -> ThirdPartyModule.Resolver {
        ThirdPartyModule.Resolver(.init(identificator: essential.identificator))
    }

    // Async transient -- child resolver wired from siblings.
    @RegisterTransient
    func coreResolver(_ resolver: Resolver) async -> CoreModule.Resolver {
        await CoreModule.Resolver(
            .init(
                identificator: essential.identificator,
                thirdParty: resolver.thirdPartyResolver
            )
        )
    }

    // Throwing transient -- intermediate value that may fail.
    @RegisterTransient
    func exerciseBundle() throws -> ExerciseBundle {
        try ExerciseBundleReader().read()
    }

    // Public dependency resolved from a transient child resolver.
    @Register
    func core(_ resolver: Resolver) async throws -> CoreModule.Resolved {
        try await resolver.coreResolver.resolve()
    }
}
```

### @Keep

Same as `@Register`, but the property on `Resolved` is **`private`**. The value is built during `resolve()` and lives as long as `Resolved` does; nothing can read it back.

Use it when the lifetime is the point and the value answers no questions -- an observer that only has to stay subscribed, a monitor that pushes rather than responds, a controller that wires itself up in its initialiser. `@RegisterTransient` is not a substitute: a transient value is cached on the `Resolver` and absent from `Resolved`, so it dies with the resolver instead of with the graph your app holds on to.

```swift
@Resolvable
struct Services {
    @Register
    func database() async throws -> Database {
        try await Database.open(path: "app.db")
    }

    // Subscribes in its initialiser. Nobody reads it -- `Resolved` holding it
    // is the whole reason the subscription stays alive.
    @Keep
    func databaseObserver(_ resolver: Resolver) async throws -> DatabaseObserver {
        try await DatabaseObserver(database: resolver.database)
    }
}

let resolved = try await Services.Resolver(.init()).resolve()

resolved.database        // fine
resolved.databaseObserver // error: 'databaseObserver' is inaccessible due to 'private' protection level
```

Only the `Resolved` property is hidden. The getter on `Resolver` keeps the container's access level, exactly like `@RegisterTransient`, so siblings can still depend on a kept value through `resolver.<name>`.

Two consequences of that `private`:

- `Resolved` gets an explicit initialiser instead of the implicit memberwise one -- a `private` stored property would otherwise drag the memberwise initialiser down to `private` as well, out of reach of the `resolve()` that has to call it. It is internal, which is what the memberwise initialiser was anyway.
- `resolve()` is **not** `@discardableResult` on a container whose only registrations are `@Keep`. Throwing the result away is exactly what would release what you asked to keep.

### @Perform

Marks a side-effect-only step with **no return value**. Runs during `resolve()` in parallel with other performables. Same shape rules as `@Register`, minus the return type, and without a `name:` override.

```swift
@Resolvable
struct ThirdParty {
    // Process-lifetime one-shot -- configure an SDK exactly once.
    @Perform(options: .once)
    func firebase() async {
        let options = FirebaseOptions.defaultOptions()!
        options.apiKey = Configuration.Firebase.apiKey
        FirebaseApp.configure(options: options)
    }

    // Depends on a sibling perform via Resolver.
    @Perform
    func firebaseAuth(_ resolver: Resolver) async throws {
        await resolver.firebase()
        try Auth.auth().useUserAccessGroup(Configuration.Firebase.accessGroup)
    }

    // Synchronous, throwing.
    @Perform
    func configure() throws {
        try ConfigurationManager.apply()
    }

    // Sibling registration consumed by the @Perform below.
    @Register
    func database() async throws -> Database {
        try await Database.open(path: "app.db")
    }

    // Per-Resolver lifetime -- depends on a sibling registration via Resolver.
    @Perform
    func importExercises(_ resolver: Resolver) async throws {
        try await ExercisesImportJob.run(database: resolver.database)
    }
}
```

## Cache Scope

Every `@Register`, `@RegisterTransient`, `@Keep`, and `@Perform` accepts an `options` parameter:

| Option | Lifetime | Use case |
|---|---|---|
| `.default` | Single `Resolver` instance | Stateful services, controllers, use cases |
| `.once` | Entire process | SDKs that must be configured exactly once (`FirebaseApp.configure`) |

```swift
@Register(options: .once)
func featureFlags() -> FeatureFlags {
    FeatureFlags()
}
```

Pass a constant. The value is re-read on every access, so deriving it from a runtime flag sends the same registration to the per-`Resolver` cache on one read and the process-wide one on the next -- leaving you with two live values under one name.

## Reaching Siblings

A registration must never call a sibling as a plain method -- neither `sibling()` nor `self.sibling()`. That bypasses the cache, builds the dependency a second time and defeats `options: .once`, so it is a compile error with a fix-it:

```swift
@Register
func database() async throws -> Database { … }

@Register
func repository() async throws -> Repository {
    try await Repository(database: database())   // error, with a fix-it
}

@Register
func repository(_ resolver: Resolver) async throws -> Repository {
    try await Repository(database: resolver.database)   // correct
}
```

Calling a same-named *local* function, or the same method on a *different* instance, is left alone.

## What the Compiler Will Stop You On

Mistakes are reported on your declaration, not inside generated code. In short, a container will not build if:

- `@Resolvable` sits on anything but a `class` or a `struct`
- a `@Register` has no return type, or returns an opaque `some P`
- a `@Perform` has a return type
- a factory is `static`, `class`, `mutating`, or generic
- a factory takes more than one parameter, or one that is not a `Resolver`
- two registrations end up exposing the same name
- a registration is called `resolve`, `Resolved`, `Resolver`, `_registrar` or `_resolvable`
- `name:` is not a legal Swift identifier
- a registration calls a sibling directly instead of going through `Resolver`
- registrations form a cycle

You also get a warning — and the thing you wrote is ignored — when an attribute sits somewhere `@Resolvable` never looks, when one function carries two registration attributes, or when `name:` / `sort:` is given something other than a literal.

## Concurrency and Isolation

Annotate the **factory**, not the generated member -- `@MainActor` and `@concurrent` stay on your method and are never copied onto the property or method the macro emits. `@MainActor` is the only one the macro reads, and only to decide whether the generated call needs `await`. A factory isolated to any other global actor will not compile; mark it `async` instead.

Reach for `@concurrent` when the factory body does heavy synchronous work -- decryption, a large decode, parser work -- that must not run on a caller sitting on `MainActor`:

```swift
@Register
@concurrent
func trainingPlanProvider(_ resolver: Resolver) async throws -> TrainingPlanProvider {
    try await TrainingPlanProvider(box: SecureBox.openJson(), storage: resolver.storage)
}
```

For plain `.init(...)` construction leave it off: it costs an executor hop and buys nothing.

**`await` alone does not hop off the actor.** Under approachable concurrency a `nonisolated async` function inherits its caller's isolation and runs its whole body there. So a graph first touched from `MainActor` launch code builds on `MainActor` unless you say otherwise -- which is why an app-wide holder is usually written `LazyAsyncThrowable { @concurrent in … }`.

`Resolved`, `Resolver` and `Registrar` are `Sendable`; your container must be too.

## Lazy Types

Resolve ships four `Sendable` lazy wrappers for deferred computation outside the macro system.

### Lazy

Synchronous, non-throwing. Evaluates under an `OSAllocatedUnfairLock` on first call.

```swift
let storage = Lazy {
    ExpensiveStorage(fileName: "data")
}

let s = storage() // computed once, memoized
```

### LazyThrowable

Synchronous, throwing. Errors are **not** cached -- failures retry on next call.

```swift
let config = LazyThrowable {
    try JSONDecoder().decode(Config.self, from: data)
}

let c = try config()
```

Both synchronous wrappers run the factory **under a non-recursive lock**. A factory that reaches back into its own wrapper aborts the process rather than hanging.

### LazyAsync

Async, non-throwing. Multiple concurrent awaiters share a single `Task`.

```swift
let settings = LazyAsync {
    await SettingsContainer.Resolver(.init()).resolve()
}

let resolved = await settings.value
```

### LazyAsyncThrowable

Async, throwing. Errors **are** cached -- first failure is permanent. Use this one whenever the graph you are wrapping can throw.

```swift
let session = LazyAsyncThrowable {
    try await Session.bootstrap()
}

let s = try await session.value
```

`Lazy` and `LazyThrowable` support `callAsFunction` -- use `lazy()` or `try lazy()`. `LazyAsync` and `LazyAsyncThrowable` additionally expose a `.value` property, so `await lazy()` and `await lazy.value` are equivalent (prefix with `try` when the factory throws).

## Composing Modules

Resolve is designed for modular apps. Each module defines its own `@Resolvable` container. Parent modules wire child resolvers as transient registrations:

```swift
@Resolvable
struct CoreAssembly {
    let identificator: Identificator

    @Register
    func database() async throws -> Database {
        try await Database.open()
    }

    @Register(options: .once)
    func featureFlags() -> FeatureFlags {
        FeatureFlags()
    }
}

@Resolvable
struct DomainAssembly {
    let core: CoreAssembly.Resolver

    @Register
    func exerciseLibrary() async throws -> ExerciseLibrary {
        try await ExerciseLibrary(database: core.database)
    }
}

@Resolvable
struct AppAssembly {
    let essential: Essential

    @RegisterTransient
    func coreResolver() -> CoreAssembly.Resolver {
        CoreAssembly.Resolver(.init(identificator: essential.identificator))
    }

    @RegisterTransient
    func domainResolver(_ resolver: Resolver) async -> DomainAssembly.Resolver {
        await DomainAssembly.Resolver(.init(core: resolver.coreResolver))
    }

    @Register
    func core(_ resolver: Resolver) async throws -> CoreAssembly.Resolved {
        try await resolver.coreResolver.resolve()
    }

    @Register
    func domain(_ resolver: Resolver) async throws -> DomainAssembly.Resolved {
        try await resolver.domainResolver.resolve()
    }
}

// Bootstrap
let resolved = try await AppAssembly.Resolver(.init(essential: essential)).resolve()
resolved.core.database
resolved.domain.exerciseLibrary
```

## App Entry Point

A common pattern is to hold the resolved graph in a lazy wrapper for the entire app lifecycle. `AppAssembly.resolve()` throws, so the throwing wrapper is the one to use:

```swift
enum Assembly {
    static let resolved = LazyAsyncThrowable {
        try await AppAssembly.Resolver(.init(essential: .live)).resolve()
    }
}

// At launch:
let app = try await Assembly.resolved.value

// Later, from any task:
let database = try await Assembly.resolved.value.core.database
```

## Behaviour to Design Around

- **Cancelling `resolve()` does not stop it.** Factories run in unstructured tasks that do not inherit cancellation, and the caller will not return early. Put a timeout inside the factory if you need one.
- **A failure is remembered.** If a factory throws, every later read of that dependency rethrows the same error without retrying — for the life of the `Resolver`, or of the process under `options: .once`. Handle retryable work inside the factory rather than expecting a second `resolve()` to fix it.
- **Only direct cycles are caught.** The compiler stops you when factories reference each other through `resolver.sibling`. A cycle built by passing `Resolver` somewhere and calling it indirectly compiles, and deadlocks.
- **`#if` hides a registration.** A `@Register` inside a conditional-compilation block is not picked up, and disappears from `Resolved` and `Resolver` without a diagnostic. Put the `#if` inside the factory body instead.

## Playground

A runnable example lives in [`Sources/Playground/main.swift`](Sources/Playground/main.swift). Run it with:

```sh
swift run Playground
```

## License

Resolve is available under the MIT license. See [LICENSE](LICENSE) for details.
