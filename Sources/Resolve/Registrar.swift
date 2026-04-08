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
 - an `ObjectIdentifier` of the container type, used to look up a *global*
   `Container<String>` shared across every `Resolver` of that type when a
   registration opts into `Options.once`.

 The combination guarantees that:

 1. `Options.default` registrations are cached for the lifetime of one
    `Resolver` instance and discarded with it.
 2. `Options.once` registrations are cached for the lifetime of the process
    and survive `Resolver` recreation.
 */
public struct Registrar: Sendable {
    /**
     Controls how long a registered value is cached.

     Pass these as the `options:` argument of `Register`, `RegisterTransient`
     or `Perform`. Prefer the static presets `Options.default` and
     `Options.once`; use the initializer only when you need to forward a
     Boolean flag from configuration.
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
         Construct directly only when you need a derived value (for example
         to forward a flag from configuration).

         - Parameter once: Cache scope. See the `once` stored property for
           the meaning.
         */
        @inlinable
        @inline(__always)
        public init(once: Bool = false) {
            self.once = once
        }

        /**
         Cache the registration for the lifetime of the owning `Resolver` only.

         This is the lifetime you almost always want for stateful services
         that hold references back into the resolver graph (databases, use
         cases, controllers).
         */
        public static let `default` = Options()

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
        public static let once = Options(once: true)

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
    @usableFromInline let typeIdentifier: ObjectIdentifier

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
          generated code passes the total number of `@Register*` and
          `@Perform` declarations on the container.
     */
    @inlinable
    public init<T>(for type: T.Type, minimumCapacity: Int = 0) {
        self.local = Container(minimumCapacity: minimumCapacity)
        self.typeIdentifier = ObjectIdentifier(type)
    }

    /**
     Resolves a throwing async dependency, caching the resulting `Task` so
     concurrent callers share a single in-flight resolution.

     This is the throwing entry point used by code generated from `@Register`,
     `@RegisterTransient`, and `@Perform` declarations on functions that are
     `async throws`.

     - Parameters:
        - name: The registration key. The generated code uses the function
          name (or the explicit `name:` passed to the macro).
        - options: Whether the value should live for the lifetime of this
          `Resolver` (`Options.default`) or the entire process
          (`Options.once`).
        - dependency: The factory closure produced by the macro.
     - Returns: The cached value (or the value produced by the first call).
     - Throws: Any error thrown by the underlying factory.
     */
    @discardableResult
    @inlinable
    public func register<V: Sendable>(for name: String, options: Options = .default, @_implicitSelfCapture _ dependency: @isolated(any) @escaping @Sendable () async throws -> V) async throws -> V {
        try await container(options: options).findOrCreate(key: name) {
            Task(operation: dependency)
        }.value
    }

    /**
     Resolves a non-throwing async dependency, caching the resulting `Task` so
     concurrent callers share a single in-flight resolution.

     Same semantics as the throwing overload, but used by code generated for
     `@Register`, `@RegisterTransient`, and `@Perform` declarations on
     functions that are `async` only.

     - Parameters:
        - name: The registration key.
        - options: Cache scope.
        - dependency: The factory closure produced by the macro.
     - Returns: The cached value (or the value produced by the first call).
     */
    @discardableResult
    @inlinable
    public func register<V: Sendable>(for name: String, options: Options = .default, @_implicitSelfCapture _ dependency: @isolated(any) @escaping @Sendable () async -> V) async -> V {
        await container(options: options).findOrCreate(key: name) {
            Task(operation: dependency)
        }.value
    }
}

extension Registrar {
    @usableFromInline
    func container(options: Options) -> Container<String> {
        options.once ? global : local
    }
}

// MARK: - Registrar
private extension Registrar {
    var global: Container<String> {
        Container.global.findOrCreate(key: typeIdentifier) { Container() }
    }
}

// MARK: - Container<ObjectIdentifier>
private extension Container<ObjectIdentifier> {
    static let global = Self()
}
