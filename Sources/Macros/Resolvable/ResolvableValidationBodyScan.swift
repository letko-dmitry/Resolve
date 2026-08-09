//
//  ResolvableValidationBodyScan.swift
//
//
//  Created by Dzmitry Letko on 09/08/2026.
//

import SwiftSyntax
import OrderedCollections

extension ResolvableValidation {
        struct BodyScan {
        struct Call {
            let node: FunctionCallExprSyntax
            let shadowable: Bool
        }

        static let empty = BodyScan(calls: [:], members: [:], shadowed: [])

        private let calls: [String: [Call]]
        private let members: [String: OrderedSet<String>]
        private let shadowed: Set<String>

        static func make(body: CodeBlockSyntax?) -> BodyScan {
            guard let body else { return .empty }

            let visitor = Visitor(viewMode: .sourceAccurate)

            visitor.walk(body)

            return .init(
                calls: Dictionary(grouping: visitor.calls) { $0.name }.mapValues { calls in calls.map { $0.call } },
                members: Dictionary(grouping: visitor.members) { $0.base }.mapValues { members in OrderedSet(members.map { $0.member }) },
                shadowed: visitor.shadowed
            )
        }

        func calls(of name: String) -> [FunctionCallExprSyntax] {
            let shadowed = shadowed.contains(name)

            return calls[name]?.compactMap { call in
                shadowed && call.shadowable ? nil : call.node
            } ?? []
        }

        func members(of base: String) -> OrderedSet<String> {
            members[base] ?? []
        }
    }
}

// MARK: - BodyScan.Visitor
extension ResolvableValidation.BodyScan {
    final class Visitor: SyntaxVisitor {
        private(set) var calls: [(name: String, call: Call)] = []
        private(set) var members: [(base: String, member: String)] = []
        private(set) var shadowed: Set<String> = []

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self) {
                calls.append((callee.baseName.text, .init(node: node, shadowable: true)))
            } else if let callee = node.calledExpression.as(MemberAccessExprSyntax.self), callee.base?.isSelf == true {
                calls.append((callee.declName.baseName.text, .init(node: node, shadowable: false)))
            }

            return .visitChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            if let base = node.base?.as(DeclReferenceExprSyntax.self) {
                members.append((base.baseName.text, node.declName.baseName.text))
            }

            return .visitChildren
        }

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            shadowed.insert(node.name.text)

            return .visitChildren
        }

        override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
            shadowed.insert(node.identifier.text)

            return .visitChildren
        }

        override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
            shadowed.insert(node.firstName.text)

            return .visitChildren
        }

        override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
            shadowed.insert((node.secondName ?? node.firstName).text)

            return .visitChildren
        }
    }
}
