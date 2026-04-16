# Resolve

A macro-based dependency injection framework for Swift. Declare your dependencies as plain methods, and Resolve generates a thread-safe, concurrent resolver at compile time.

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

- macOS 14+ / iOS 17+ / watchOS 10+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/letko-dmitry/Resolve.git", branch: "master")
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
- **`Resolved`** -- an immutable, `Sendable` aggregate holding all resolved dependencies. This is what you pass around your app.

All non-transient registrations start concurrently via `async let`. All `@Perform` steps run in parallel inside a task group. Dependencies that reference siblings through `Resolver` naturally await each other, forming an implicit DAG.

## Macros

### @Register

Marks a method as a dependency factory. The return value is cached and exposed on `Resolved`.

Methods may be synchronous, `async`, `throws`, or `async throws`. They may take zero parameters or a single `Resolver` parameter to pull sibling dependencies.

```swift
@Resolvable
struct Services {
    let identificator: Identificator

    // Synchronous, no dependencies.
    @Register
    func featureFlags() -> FeatureFlags {
        FeatureFlags()
    }

    // Synchronous, depends on a sibling via Resolver.
    @Register
    func exerciseDataSource(_ resolver: Resolver) -> ExerciseDataSource {
        ExerciseDataSource(bundle: resolver.exerciseBundle)
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

### @RegisterTransient

Same as `@Register`, but the value is **not** included in `Resolved`. Use for intermediate wiring -- child resolvers, builders, or helpers needed only during graph construction. Still cached and callable on `Resolver`.

```swift
@Resolvable
struct AppAssembly {
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

### @Perform

Marks a side-effect-only step with no return value. Runs during `resolve()` in parallel with other performables.

```swift
@Resolvable
struct ThirdParty {
    let identificator: Identificator

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

    // Per-Resolver lifetime -- runs on every resolve().
    @Perform
    func importExercises(_ resolver: Resolver) async throws {
        try await ExercisesImportJob.run(database: resolver.database)
    }
}
```

## Cache Scope

Every `@Register`, `@RegisterTransient`, and `@Perform` accepts an `options` parameter:

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

### LazyAsync

Async, non-throwing. Multiple concurrent awaiters share a single `Task`.

```swift
let appGraph = LazyAsync {
    await AppContainer.Resolver(.init()).resolve()
}

let resolved = await appGraph.value
```

### LazyAsyncThrowable

Async, throwing. Errors **are** cached -- first failure is permanent.

```swift
let session = LazyAsyncThrowable {
    try await Session.bootstrap()
}

let s = try await session.value
```

All lazy types support `callAsFunction`, so `lazy()` and `lazy.value` are equivalent (for async variants, `await lazy()` and `await lazy.value`).

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

    @Perform
    func launch(_ resolver: Resolver) async throws {
        try await LaunchAssembly.Resolver(
            .init(core: resolver.coreResolver, domain: resolver.domainResolver)
        ).resolve()
    }
}

// Bootstrap
let resolved = try await AppAssembly.Resolver(.init(essential: essential)).resolve()
resolved.core.database
resolved.domain.exerciseLibrary
```

## App Entry Point

A common pattern is to hold the resolved graph in a `LazyAsync` for the entire app lifecycle:

```swift
enum Assembly {
    static let resolved = LazyAsync {
        await AppAssembly.Resolver(.init(config: .live)).resolve()
    }
}

// At launch:
let app = await Assembly.resolved.value

// Later, from any task:
let db = await Assembly.resolved.value.database
```
