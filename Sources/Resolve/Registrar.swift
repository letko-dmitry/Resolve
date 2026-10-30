//
//  Registrar.swift
//
//
//  Created by Dzmitry Letko on 01/10/2023.
//

import os.lock

/**
 The runtime half of `Resolvable`: what a generated `Resolver` calls into.

 You usually do not interact with `Registrar` directly. Its types are public
 because the generated code lives in the consumer's module and must be able to
 refer to them.

 Every generated `Resolver` declares a private `Registrations` class with one
 `Registration` or `RegistrationThrowable` per `Register`, `RegisterTransient`,
 `Keep` and `Perform`, and keeps two instances of it in a `Registrar.Storage`:

 - a *local* one, used by `Options.default` registrations and tied to the
   lifetime of the `Resolver`;
 - a *global* one shared by every `Resolver` of the same container type, the
   local one of the first of them, used by registrations that opt into
   `Options.once`.

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

         - Warning: The `options:` expression is evaluated each time a `Resolver`
           is created, and the value decides *which* instance of the
           registrations answers. Deriving it from something that can change — a
           runtime flag, a configuration lookup — sends the same registration to
           the local instance for one `Resolver` and to the process-wide one for
           the next, producing two live values under one name. Whatever you pass
           must be constant for the lifetime of the process.

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

    /**
     The registrations of one generated `Resolver`: its own and the
     process-wide ones shared by every `Resolver` of the container type.

     A registration is reached as a dynamic member, `_registrar.database`, which
     is a key path to the stored property inlined at the call site: it compiles
     to a plain field load, with no key to hash and nothing to cast. The
     registrations themselves never change; each one guards its own state.

     Generated code creates one per `Resolver`. You should not create one from
     hand-written code.
     */
    @dynamicMemberLookup
    public struct Storage<Registrations: AnyObject & Sendable>: Sendable {
        // References, so that the copies of a `Resolver` – one in every task it starts – share one set of registrations.
        @usableFromInline let local: Registrations
        @usableFromInline let global: Registrations

        /**
         Creates the storage of a `Resolver`.

         - Parameter registrations: Every registration of the container, none of
           them started. Those of the first `Resolver` of a container type are
           also the process-wide registrations.
         */
        @export(implementation)
        public init(_ registrations: Registrations) {
            self.local = registrations
            self.global = Self.global(registrations)
        }

        // Both subscripts are always inlined: the key path literal folds into a field load only at the call site, and on
        // a class root the inliner would otherwise leave a call that builds the key path at run time.

        /**
         The non-throwing registration behind a stored property: the
         process-wide one for `Options.once`, the resolver's own otherwise.
         */
        @inline(always)
        @export(implementation)
        public subscript<R, V>(dynamicMember registration: KeyPath<Registrations, Registration<R, V>>) -> Registration<R, V> {
            let local = local[keyPath: registration]

            return local.once ? global[keyPath: registration] : local
        }

        /**
         The throwing registration behind a stored property: the process-wide
         one for `Options.once`, the resolver's own otherwise.
         */
        @inline(always)
        @export(implementation)
        public subscript<R, V>(dynamicMember registration: KeyPath<Registrations, RegistrationThrowable<R, V>>) -> RegistrationThrowable<R, V> {
            let local = local[keyPath: registration]

            return local.once ? global[keyPath: registration] : local
        }
    }
}

// MARK: - Registrar.Storage
extension Registrar.Storage {
    // The process-wide registrations of a container type: those of the first `Resolver` that asks.
    @usableFromInline
    static func global(_ registrations: Registrations) -> Registrations {
        Registrar.globals.withLock { globals in
            let type = ObjectIdentifier(Registrations.self)

            if let global = globals[type] as? Registrations {
                return global
            }

            // Not `globals[type] = registrations`: the optional subscript setter also pulls the removal path into the binary.
            globals.updateValue(registrations, forKey: type)

            return registrations
        }
    }
}

// MARK: - Registrar
private extension Registrar {
    static let globals = OSAllocatedUnfairLock(initialState: [ObjectIdentifier: any Sendable]())
}
