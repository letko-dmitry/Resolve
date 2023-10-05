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
    @Register()
    func database() async throws -> String {
        return String()
    }
}

