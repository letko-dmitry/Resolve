//
//  StringCollectionBuilder.swift
//  
//
//  Created by Dzmitry Letko on 17/10/2023.
//

import Foundation

@resultBuilder
struct StringCollectionBuilder {
    static func buildBlock(_ components: [String]...) -> [String] {
        buildArray(components)
    }
    
    static func buildEither(first component: [String]) -> [String] {
        component
    }

    static func buildEither(second component: [String]) -> [String] {
        component
    }
    
    static func buildArray(_ components: [[String]]) -> [String] {
        components.flatMap { $0 }
    }
    
    static func buildExpression(_ expression: String) -> [String] {
        [expression]
    }
    
    static func buildFinalResult(_ component: [String]) -> [String] {
        component.filter { !$0.isEmpty }
    }
}
