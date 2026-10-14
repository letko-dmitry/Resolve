//
//  Registrar.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

/**
 Thread-safe per-type cache used by code generated from `Resolvable`.

 You usually do not interact with `Registrar` directly. The macros emit a
 private `_registrar` property on each generated `Resolver`, and that property
 holds the only `Registrar` you need. The type is public because the generated
 code lives in the consumer's module and must be able to refer to it.

 Internally, every `Registrar` owns:

 - a *local* `Container<String>` keyed by registration name, used for
   `Options.default` registrations and tied to the lifetime of the parent
   `Resolver`;
 - a *global* `Container<String>` shared across every `Resolver` of the same
   container type, looked up once when the `Registrar` is created and used by
   registrations that opt into `Options.once`.

 The combination guarantees that:

 1. `Options.default` registrations are cached for the lifetime of one
    `Resolver` instance and discarded with it.
 2. `Options.once` registrations are cached for the lifetime of the process
    and survive `Resolver` recreation.
 */
public struct Registrar: Sendable {
    /**
     Controls how long a registered value is cached.

     Pass these as the `options:` argument of `Register`, `RegisterTransient`,
     `Keep` or `Perform`. Prefer the static presets `Options.default` and
     `Options.once`.
     */
    public struct Options: Sendable {
        /**
         When `true`, the registration is cached in the process-wide container
         keyed by the enclosing type, so it survives `Resolver` recreation and
         is shared across every `Resolver` of that type.

         When `false`, the registration is cached only in the local
         per-`Resolver` container.
         */
        public let once: Bool

        /**
         Creates an `Options` value.

         Prefer the static presets `Options.default` and `Options.once`.

         - Warning: The generated getter re-evaluates the `options:` expression
           on every access, and the value decides *which* container answers.
           Deriving it from something that can change — a runtime flag, a
           configuration lookup — sends the same registration to the local
           container on one access and to the process-wide one on the next,
           producing two live values under one name. Whatever you pass must be
           constant for the lifetime of the registration.

         - Parameter once: Cache scope. See the `once` stored property for
           the meaning.
         */
        @inline(always)
        @export(implementation)
        public init(once: Bool = false) {
            self.once = once
        }

        /**
         Cache the registration for the lifetime of the owning `Resolver` only.

         This is the lifetime you almost always want for stateful services
         that hold references back into the resolver graph (databases, use
         cases, controllers).
         */
        @inline(always)
        @export(implementation)
        public static var `default`: Options { Options() }

        /**
         Cache the registration for the entire process lifetime, keyed by the
         enclosing container type.

         Use this for resources that **must** be created exactly once per
         process — for example SDKs that misbehave when configured twice
         (`FirebaseApp.configure`, Qonversion init), or values that hold
         hardware/file handles which cannot be safely re-acquired.

         Even if a fresh `Resolver` is constructed later, the cached value
         from the very first call is reused.
         */
        @inline(always)
        @export(implementation)
        public static var once: Options { Options(once: true) }

        /**
         Deprecated alias for `once`.

         Existing call sites should migrate to `Options.once`. The compiler
         fix-it produced by `@available(*, deprecated, renamed:)` performs
         the rename automatically.
         */
        @available(*, deprecated, renamed: "once")
        public static var singleton: Options { .once }
    }

    @usableFromInline let local: Container<String>
    @usableFromInline let global: Container<String>

    /**
     Creates a `Registrar` for the given container type.

     Generated code calls this initialiser exactly once per `Resolver`
     instance. You should not call it from hand-written code.

     - Parameters:
        - type: The container type the registrar belongs to. Used as the key
          for `Options.once` lookups, so two different containers do not
          share global state even if their registration names collide.
        - minimumCapacity: A hint that pre-sizes the underlying dictionary to
          avoid rehashing during the first burst of registrations. The
          generated code passes the total number of registration and
          `@Perform` declarations on the container.
     */
    @inlinable
    public init<T>(for type: T.Type, minimumCapacity: Int = 0) {
        self.local = Container(minimumCapacity: minimumCapacity)
        self.global = .global(for: ObjectIdentifier(type))
    }

    /**
     Resolves a throwing async dependency, caching the resulting `Task` so
     concurrent callers share a single in-flight resolution.

     This is the throwing entry point used by code generated from `@Register`,
     `@RegisterTransient`, `@Keep`, and `@Perform` declarations on functions
     that are `async throws`.

     - Parameters:
        - name: The registration key. The generated code uses the function
          name (or the explicit `name:` passed to the macro).
        - options: Whether the value should live for the lifetime of this
          `Resolver` (`Options.default`) or the entire process
          (`Options.once`).
        - resolver: The generated `Resolver`, handed back to `dependency`.
          Passing it instead of capturing it keeps the macro's closure free of
          captures, so an access that hits the cache allocates nothing.
        - dependency: The factory closure produced by the macro.
     - Returns: The cached value (or the value produced by the first call).
     - Throws: Any error thrown by the underlying factory.
     */
    @discardableResult
    @export(implementation)
    public func register<R: Sendable, V: Sendable>(for name: String, options: Options = .default, _ resolver: R, _ dependency: @escaping @Sendable (R) async throws -> V) async throws -> V {
        try await findOrCreate(for: name, options: options) {
            Self.task(resolver, dependency)
        }.value
    }

    /**
     Resolves a non-throwing async dependency, caching the resulting `Task` so
     concurrent callers share a single in-flight resolution.

     Same semantics as the throwing overload, but used by code generated for
     `@Register`, `@RegisterTransient`, `@Keep`, and `@Perform` declarations on
     functions that are `async` only.

     - Parameters:
        - name: The registration key.
        - options: Cache scope.
        - resolver: The generated `Resolver`, handed back to `dependency`.
        - dependency: The factory closure produced by the macro.
     - Returns: The cached value (or the value produced by the first call).
     */
    @discardableResult
    @export(implementation)
    public func register<R: Sendable, V: Sendable>(for name: String, options: Options = .default, _ resolver: R, _ dependency: @escaping @Sendable (R) async -> V) async -> V {
        await findOrCreate(for: name, options: options) {
            Self.task(resolver, dependency)
        }.value
    }
}

// Deliberately not inlinable: the inlined `register` shell only calls in here, so the lookup and the generic
// `Task` creation – with its reabstraction thunks – are emitted once in this module instead of in every getter.
extension Registrar {
    @usableFromInline
    func findOrCreate<V: Sendable>(for name: String, options: Options, _ value: @Sendable () -> V) -> V {
        (options.once ? global : local).findOrCreate(key: name, value: value)
    }

    @usableFromInline
    static func task<R: Sendable, V: Sendable>(_ resolver: R, _ dependency: @escaping @Sendable (R) async throws -> V) -> Task<V, any Error> {
        Task { try await dependency(resolver) }
    }

    @usableFromInline
    static func task<R: Sendable, V: Sendable>(_ resolver: R, _ dependency: @escaping @Sendable (R) async -> V) -> Task<V, Never> {
        Task { await dependency(resolver) }
    }
}

// MARK: - Container<String>
extension Container<String> {
    @usableFromInline
    static func global(for type: ObjectIdentifier) -> Self {
        Container<ObjectIdentifier>.globals.findOrCreate(key: type) { Self() }
    }
}

// MARK: - Container<ObjectIdentifier>
private extension Container<ObjectIdentifier> {
    static let globals = Self()
}
