//
//  ResolvableValidation.swift
//
//
//  Created by Dzmitry Letko on 05/10/2023.
//

import OrderedCollections
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

struct ResolvableValidation {
    struct Resolvables {
        let registrables: [Registrable]
        let performables: [Performable]
    }

    let registrables: [Registrable]
    let performables: [Performable]

    func validate(in context: some MacroExpansionContext) -> Resolvables {
        DirectUseReport.make(registrables: registrables, performables: performables).print(in: context)
        ReservedNameReport.make(registrables: registrables, performables: performables).print(in: context)

        let uniqueness = UniquenessReport.make(registrables: registrables, performables: performables)

        uniqueness.print(in: context)

        let registrables = registrables.filter { !uniqueness.dropped.contains($0.node) }
        let performables = performables.filter { !uniqueness.dropped.contains($0.node) }

        CycleReport.make(registrables: registrables, performables: performables).print(in: context)

        return .init(registrables: registrables, performables: performables)
    }
}
