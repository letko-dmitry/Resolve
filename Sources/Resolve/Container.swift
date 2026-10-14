//
//  Container.swift
//  
//
//  Created by Dzmitry Letko on 14/10/2023.
//

import os.lock

@usableFromInline
struct Container<Key: Sendable & Hashable>: Sendable {
    private let values: OSAllocatedUnfairLock<[Key: any Sendable]>

    @usableFromInline
    init(minimumCapacity: Int = 0) {
        values = OSAllocatedUnfairLock(initialState: .init(minimumCapacity: minimumCapacity))
    }
    
    func findOrCreate<V: Sendable>(key: Key, value: @Sendable () -> V) -> V {
        values.withLock { values in
            if let value = values[key] as? V {
                return value
            }
            
            let value = value()

            // Not `values[key] = value`: the optional subscript setter also pulls the removal path into the binary.
            values.updateValue(value, forKey: key)
            
            return value
        }
    }
}
