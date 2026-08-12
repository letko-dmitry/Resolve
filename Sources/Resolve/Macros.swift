//
//  Macros.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

/**
 Marks a `struct` or `class` as a dependency-injection container and generates
 two nested types at compile time:

 - `Resolved` — a `Sendable` value-type aggregate of every dependency that
   was registered with `Register` or `Keep` (transient registrations are
   intentionally excluded). Once `Resolver.resolve()` returns, callers reach
   individual services through this aggregate — every one of them but a `Keep`,
   which is stored as a `private` property and only kept alive.
 - `Resolver` — a `Sendable` façade that wraps the original container instance
   and exposes:
     * one async getter per `Register` / `RegisterTransient` / `Keep`
       declaration,
     * one async method per `Perform` declaration,
     * a `resolve()` method that brings up the whole graph and returns a
       `Resolved` value.

 ## Concurrency model of the generated `resolve()`

 - Every non-transient `@Register` getter is started concurrently with an
   `async let` binding, and the bindings are awaited together when the
   `Resolved` aggregate is built.
 - Every `@Perform` method is launched in parallel inside a
   `withDiscardingTaskGroup` (or `withThrowingDiscardingTaskGroup` when at
   least one performable throws), so independent setups proceed in parallel
   alongside the registrations.

 Each annotated method is invoked **at most once per `Resolver` lifetime** by
 default. Pass `options: .once` to a registration or performable to widen the
 cache to the entire process lifetime — the very first call wins forever.

 ## Usage

 ```swift
 import Resolve

 @Resolvable
 struct AssemblySystemCore {
     let identificator: AssemblyEssentialIdentificator
     let thirdParty: AssemblySystemThirdParty.Resolver

     @Register
     func database() async throws -> any AbstractCoreDataStack {
         try await CoreDataStackBuilder(/* … */).make()
     }

     @Register(options: .once)
     func applicationFeaturesController() -> any AbstractApplicationFeaturesController {
         ApplicationFeaturesController()
     }
 }

 // Build and consume:
 let resolver = AssemblySystemCore.Resolver(.init(identificator: …, thirdParty: …))
 let resolved = try await resolver.resolve()
 let db = resolved.database // already a fully-constructed value
 ```

 - Parameter sort: When `true` (the default) the generated `Resolved`
   properties and `async let` bindings are emitted in alphabetical order of the
   *registration* name — the `name:` override when present, otherwise the
   function name. Set to `false` to keep declaration order. The choice changes
   the order of the stored properties on `Resolved`, and with it the order of
   the memberwise initialiser; it does not change what is built or when,
   because every registration is awaited concurrently either way. The argument
   must be a boolean literal — anything else is ignored with a warning.

 - Important: The macro must be attached to a `struct` or `class`. Every other
   declaration — an `extension`, an `enum`, an `actor`, a `protocol` — is
   rejected at expansion time with an explicit diagnostic.

 - Important: Only functions declared directly in the body of the annotated type
   are inspected. A `Register` or `Perform` placed in an extension, inside a
   nested type, or on a top-level function expands to nothing, and the macro
   warns at the attribute rather than dropping the dependency silently. Members
   wrapped in `#if` are still skipped without a warning.

 - Important: A registration must never call a sibling registration as a plain
   method — neither `sibling()` nor `self.sibling()`. Doing so bypasses the
   cache, builds the dependency a second time and defeats
   `Registrar.Options.once`, so it is rejected with a fix-it that rewrites the
   call to go through a `Resolver` parameter. Calling a same-named *local*
   function, or the same method on a different instance, is left alone.

 - Important: `Resolved` and `Resolver` repeat the access level of the container,
   so a `public` container produces types other modules can name. A `public`
   container must also be explicitly `Sendable`: public types get no implicit
   conformance, and `Resolver` stores one. A registration may not be called
   `resolve`, `Resolved`, `Resolver`, `_registrar` or `_resolvable` — those
   names are taken by the generated members.

 - Note: `resolve()` is marked `@discardableResult` only when `Resolved` would
   be empty — that is, when the container declares no non-transient
   `Register`. Otherwise the aggregate carries the dependencies you asked for
   and discarding it is almost certainly a mistake.
 */
@attached(member, names: named(Resolved), named(Resolver))
public macro Resolvable(sort: Bool = true) = #externalMacro(module: "Macros", type: "Resolvable")

/**
 Registers a method as a dependency factory inside a `Resolvable` container.

 The method is called **once per `Resolver` lifetime** (or once per process
 lifetime when `options: .once` is supplied). The returned value is cached and
 also exposed on the generated `Resolved` aggregate, so consumers reach it
 through `resolved.<methodName>`.

 ## Method requirements

 - Must declare a return type, and a concrete one: an opaque `some P` cannot be
   a stored property of `Resolved` and is rejected.
 - Must be an instance method. `static`, `class`, `mutating` and generic
   declarations are rejected — the generated code reaches the factory through a
   stored instance of the container.
 - May be `async`, `throws`, or both. Effects are propagated transparently
   into the generated getter and `resolve()`.
 - May take **at most one** parameter, and only of type `Resolver`. The
   generated code passes `self` (the `Resolver` itself) so the method can pull
   sibling registrations from the same container.

 Every generated getter is `async`, whatever the factory looks like. A factory
 that reads `resolver.somethingElse` is therefore `async` as well, and
 `async throws` when the sibling it reads can throw.

 ## Isolation

 Isolation annotations describe **the factory**, and the macro never copies them
 onto the generated property or method. That is deliberate: the accessor exists
 to hand back an already-built `Sendable` value, so pinning it to an actor would
 constrain every reader for no reason. The macro reads `@MainActor` for exactly
 one purpose — deciding whether the generated call needs `await` — and reads
 nothing else. A factory isolated to some other global actor will not compile;
 mark it `async` instead.

 `@concurrent` (Swift 6.2) is likewise the factory's business. This package
 builds with approachable concurrency, so a `nonisolated async` function
 *inherits its caller's isolation* — `await` alone does **not** hop off the
 actor. Annotate a factory with `@concurrent` when its body does heavy
 synchronous work that must not run on a caller that is on `MainActor`. It costs
 an executor hop, so leave it off for plain construction.

 ## Examples

 ```swift
 // Per-Resolver lifetime, no dependencies on siblings. `@concurrent` because
 // opening the stack does heavy synchronous work the caller must not absorb.
 @Register
 @concurrent
 func database() async throws -> any AbstractCoreDataStack { … }

 // Per-Resolver lifetime, depends on sibling registrations through `resolver`.
 @Register
 func exerciseLibraryController(_ resolver: Resolver) async throws -> any ExerciseLibraryController {
     try await ExerciseLibraryController(
         database: resolver.database,
         source: resolver.exerciseImportedDataSource
     )
 }

 // Application-wide singleton.
 @Register(options: .once)
 func applicationFeaturesController() -> any AbstractApplicationFeaturesController {
     ApplicationFeaturesController()
 }
 ```

 - Parameters:
    - name: Optional override for the registration identifier. When supplied,
      the generated `Resolver` exposes the dependency under this name (instead
      of the function name), the corresponding property on the generated
      `Resolved` aggregate is renamed to match, and the internal `Registrar`
      cache uses the same string as its key. Use this to decouple the public
      surface of the generated `Resolver` / `Resolved` from the underlying
      factory function name. The argument must be a **string literal** holding a
      legal Swift identifier — it is spliced into a property declaration. A
      non-literal is ignored with a warning; an illegal identifier is an error.
    - options: `Registrar.Options` controlling cache scope. Use
      `Registrar.Options.once` for application-lifetime singletons; otherwise
      leave at `Registrar.Options.default`. The expression is re-evaluated on
      every access, so it must be constant for a given registration.

 - SeeAlso: `RegisterTransient`, `Keep`, `Perform`, `Resolvable`.
 */
@attached(peer)
public macro Register(name: String? = nil, options: Registrar.Options = .default) = #externalMacro(module: "Macros", type: "Register")

/**
 Registers a method as a dependency factory whose result is **not** stored on
 the generated `Resolved` aggregate.

 Use this for intermediate values that are needed only during graph
 construction — typically child `Resolver` instances that get passed into
 sibling registrations, or auxiliary builders that should not be exposed
 publicly. The factory is still cached for the lifetime of the parent
 `Resolver` (or globally with `options: .once`), so calling it from several
 sibling registrations is safe and produces a single shared value.

 The method has the same shape requirements as `Register`: a return type,
 zero or one `Resolver` parameter, and any combination of `async`/`throws`.

 ## Example

 ```swift
 @Resolvable
 struct AssemblySystem {
     let essential: AssemblyEssential

     // Public dependency that other modules consume.
     @Register
     func core(_ resolver: Resolver) async throws -> AssemblySystemCore.Resolved {
         try await resolver.coreResolver.resolve()
     }

     // Helper child resolver — needed by `core` and several other registrations,
     // but not part of the public `Resolved` surface.
     @RegisterTransient
     func coreResolver(_ resolver: Resolver) async -> AssemblySystemCore.Resolver {
         await AssemblySystemCore.Resolver(
             .init(
                 identificator: essential.identificator,
                 thirdParty: resolver.thirdPartyResolver
             )
         )
     }
 }
 ```

 - Parameters:
    - name: Optional override for the registration identifier. When supplied,
      the generated `Resolver` exposes the dependency under this name (instead
      of the function name) and the internal `Registrar` cache uses the same
      string as its key. Identical semantics to `Register(name:)`.
    - options: `Registrar.Options` controlling cache scope.

 - Important: Transient registrations are still callable on the generated
   `Resolver` (e.g. `resolver.coreResolver`). They are simply omitted from
   `Resolved`. Treat them as private wiring helpers.

 - SeeAlso: `Register`, `Keep`, `Perform`, `Resolvable`.
 */
@attached(peer)
public macro RegisterTransient(name: String? = nil, options: Registrar.Options = .default) = #externalMacro(module: "Macros", type: "Register")

/**
 Registers a method as a dependency factory whose result is stored on the
 generated `Resolved` aggregate as a **private** property.

 This is `Register` with the reading end taken away. The value is built during
 `resolve()` exactly like any other registration, and it is held for as long as
 the `Resolved` value is held — but nothing outside `Resolved` can read it, so
 the dependency exists only to stay alive.

 Reach for it when the *lifetime* is the whole point and the value has no
 callers: an observer that only has to remain subscribed, a monitor that pushes
 rather than answers, a controller that wires itself up in its initialiser.
 `RegisterTransient` cannot do this — a transient value is cached on the
 `Resolver` and dropped from `Resolved`, so it dies with the resolver rather
 than with the graph the app holds.

 The method has the same shape requirements as `Register`: a return type,
 zero or one `Resolver` parameter, and any combination of `async`/`throws`.

 ## Example

 ```swift
 @Resolvable
 struct AssemblySystem {
     @Register
     func database() async throws -> any AbstractCoreDataStack {
         try await CoreDataStackBuilder().make()
     }

     // Subscribes in its initialiser and never answers a question. Nothing
     // reads it; `Resolved` holding it is what keeps the subscription alive.
     @Keep
     func databaseObserver(_ resolver: Resolver) async throws -> DatabaseObserver {
         try await DatabaseObserver(database: resolver.database)
     }
 }
 ```

 - Parameters:
    - name: Optional override for the registration identifier. Identical
      semantics to `Register(name:)` — it renames the property on `Resolved`
      (still `private`) and the getter on `Resolver`, and becomes the cache key.
    - options: `Registrar.Options` controlling cache scope.

 - Important: Only the property on `Resolved` is private. The getter on the
   generated `Resolver` keeps the container's access level, exactly like
   `RegisterTransient`, so sibling factories can still reach the value through
   `resolver.<name>`.

 - Important: A container with at least one `Keep` gets an explicit initialiser
   on `Resolved` instead of the implicit memberwise one, because a `private`
   stored property would otherwise make that initialiser `private` too. It is
   internal, which is the visibility the memberwise initialiser had anyway.

 - Note: `resolve()` is not `@discardableResult` for a container whose only
   registrations are `Keep`. Discarding the returned `Resolved` is precisely
   what would release the dependencies it was asked to hold.

 - SeeAlso: `Register`, `RegisterTransient`, `Resolvable`.
 */
@attached(peer)
public macro Keep(name: String? = nil, options: Registrar.Options = .default) = #externalMacro(module: "Macros", type: "Register")

/**
 Marks a method as a side-effect-only step that runs as part of resolution.

 Performable methods do **not** declare a return type — they exist purely for
 their side effects (configuring SDKs, kicking off background imports,
 attaching observers, registering plugins, …). They are invoked exactly once
 per `Resolver` lifetime by default, or once per process lifetime when
 `options: .once` is supplied.

 During `resolve()` every `@Perform` method is launched concurrently inside a
 `withDiscardingTaskGroup` (or `withThrowingDiscardingTaskGroup` when at least
 one performable throws) so independent setups proceed in parallel.

 ## Method requirements

 - Must **not** declare a return type.
 - May be `async`, `throws`, or both.
 - May take at most one parameter of type `Resolver` to pull sibling
   registrations.

 ## Example

 ```swift
 @Resolvable
 struct AssemblySystemThirdParty {
     let identificator: AssemblyEssentialIdentificator

     // `@concurrent` keeps a third-party initialiser off the caller's actor.
     @Perform(options: .once)
     @concurrent
     func firebase() async {
         FirebaseApp.configure(options: …)
     }

     @Perform
     func firebaseAuth(resolver: Resolver) async throws {
         await resolver.firebase()
         try Auth.auth().useUserAccessGroup(…)
     }
 }
 ```

 - Parameter options: `Registrar.Options` controlling cache scope. Use
   `Registrar.Options.once` for setups that must happen exactly once per
   process (e.g. `FirebaseApp.configure`).

 - SeeAlso: `Register`, `RegisterTransient`, `Keep`, `Resolvable`.
 */
@attached(peer)
public macro Perform(options: Registrar.Options = .default) = #externalMacro(module: "Macros", type: "Perform")
