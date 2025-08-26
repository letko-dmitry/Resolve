//
//  OSAllocatedUnfairLock.swift
//  Resolve
//
//  Created by Dzmitry Letko on 26/08/2025.
//

import os.lock

extension OSAllocatedUnfairLock {
    @discardableResult
    func withAdaptiveSpinIfPossible<T: Sendable>(_ body: @Sendable (inout State) throws -> T) rethrows -> T {
        if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            try withLock(flags: .adaptiveSpin, body)
        } else {
            try withLock(body)
        }
    }
    
    @discardableResult
    func withAdaptiveSpinUncheckedIfPossible<T: Sendable>(_ body: (inout State) throws -> T) rethrows -> T {
        if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            try withLockUnchecked(flags: .adaptiveSpin, body)
        } else {
            try withLockUnchecked(body)
        }
    }
}
