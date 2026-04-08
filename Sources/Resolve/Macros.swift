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
   was registered with `Register` (transient registrations are intentionally
   excluded). Once `Resolver.resolve()` returns, callers reach individual
   services through this aggregate.
 - `Resolver` — a `Sendable` façade that wraps the original container instance
   and exposes:
     * one async getter per `Register` / `RegisterTransient` declaration,
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
     @concurrent
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
   properties and `async let` bindings are emitted in alphabetical order of
   the method name. Set to `false` to keep declaration order. Either choice
   produces the same runtime behaviour because every registration is awaited
   concurrently — `sort` is purely a cosmetic / diff-stability knob for the
   generated source.

 - Important: The macro must be attached to a `struct` or `class`. An
   `extension` is rejected at expansion time with an explicit diagnostic;
   attaching to other named nominal types (enum, actor, protocol) is not
   supported and will produce code that does not compile, even though the
   macro itself will not refuse the input.
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

 - Must declare a return type. The return type becomes the type of the
   property on `Resolved`.
 - May be `async`, `throws`, or both. Effects are propagated transparently
   into the generated getter and `resolve()`.
 - May take **at most one** parameter, and only of type `Resolver`. The
   generated code passes `self` (the `Resolver` itself) so the method can pull
   sibling registrations from the same container.

 ## Examples

 ```swift
 // Per-Resolver lifetime, no dependencies on siblings.
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
      factory function name.
    - options: `Registrar.Options` controlling cache scope. Use
      `Registrar.Options.once` for application-lifetime singletons; otherwise
      leave at `Registrar.Options.default`.

 - SeeAlso: `RegisterTransient`, `Perform`, `Resolvable`.
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
     @concurrent
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

 - SeeAlso: `Register`, `Perform`, `Resolvable`.
 */
@attached(peer)
public macro RegisterTransient(name: String? = nil, options: Registrar.Options = .default) = #externalMacro(module: "Macros", type: "Register")

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

 - SeeAlso: `Register`, `RegisterTransient`, `Resolvable`.
 */
@attached(peer)
public macro Perform(options: Registrar.Options = .default) = #externalMacro(module: "Macros", type: "Perform")
