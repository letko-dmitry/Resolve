//
//  main.swift
//  
//
//  Created by Dzmitry Letko on 04/10/2023.
//

import Foundation
import Resolve

@Resolvable
struct Container {
    @Register
    func database() async -> String {
        return String()
    }
    
    @Register(options: .once)
    func pipeline() async -> String {
        return String()
    }
    
    @Register
    func network(resolver: Resolver) async throws -> String {
        return String()
    }
    
    @Perform
    func configure() throws {
        
    }
    
    @Perform
    func firebase() throws {
        
    }
}
