//
//  main.swift
//
//
//  Created by Dzmitry Letko on 04/10/2023.
//

import Foundation
import Resolve

struct Logger: Sendable {
    let category: String

    func log(_ message: String) {
        print("[\(category)] \(message)")
    }
}

struct Database: Sendable {
    let logger: Logger
}

struct Pipeline: Sendable {
    let database: Database
}

@Resolvable
struct Container {
    let category: String

    @Register
    func logger() -> Logger {
        Logger(category: category)
    }

    @Register
    func database(_ resolver: Resolver) async -> Database {
        await Database(logger: resolver.logger)
    }

    @Register(name: "pipeline")
    func makePipeline(_ resolver: Resolver) async -> Pipeline {
        await Pipeline(database: resolver.database)
    }

    @RegisterTransient
    func migrator(_ resolver: Resolver) async -> Logger {
        await resolver.logger
    }

    @Perform(options: .once)
    func migrate(_ resolver: Resolver) async {
        await resolver.migrator.log("migrated once per process")
    }
}

let resolver = Container.Resolver(.init(category: "playground"))
let resolved = await resolver.resolve()

resolved.logger.log("logger resolved")
resolved.pipeline.database.logger.log("pipeline resolved through the graph")

// `migrator` is transient: reachable on Resolver, absent from Resolved.
await resolver.migrator.log("transient resolved on demand")

// The same Resolver hands out the very same instances.
let again = await resolver.resolve()

print("cached:", again.logger.category == resolved.logger.category)
