//
//  CurrentValueAsyncSubject.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/13/23.
//

import Foundation

actor CurrentValueAsyncSubject<Element: Sendable>: Equatable {
    static func == (lhs: CurrentValueAsyncSubject<Element>, rhs: CurrentValueAsyncSubject<Element>) -> Bool {
        lhs.uuid == rhs.uuid
    }
    
    private(set) var value: Element?
    private let uuid: UUID = .init()
    
    var stream: AsyncStream<Element> {
        let (stream, continuation) = AsyncStream<Element>.makeStream()
        let key = UUID()
        
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.remove(key: key)
            }
        }
        
        continuations[key] = continuation
        
        return stream
    }
    
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = .init()
    
    deinit {
        continuations.values.forEach { continuation in
            continuation.finish()
        }
    }
    
    func callAsFunction() -> AsyncStream<Element> {
        stream
    }
    
    func yield(with result: Result<Element, Never>) {
        if case .success(let newValue) = result {
            value = newValue
        }
        
        continuations.values.forEach { continuation in
            continuation.yield(with: result)
        }
    }
    
    func yield(_ value: Element) {
        self.value = value
        
        continuations.values.forEach { continuation in
            continuation.yield(value)
        }
    }
    
    private func remove(key: UUID) {
        continuations.removeValue(forKey: key)
    }
}
