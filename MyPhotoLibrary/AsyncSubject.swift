//
//  AsyncSubject.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/13/23.
//

import Foundation

actor AsyncSubject<Element: Sendable> {
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
        continuations.values.forEach { continuation in
            continuation.yield(with: result)
        }
    }
    
    func yield(_ value: Element) {
        continuations.values.forEach { continuation in
            continuation.yield(value)
        }
    }
    
    private func remove(key: UUID) {
        continuations.removeValue(forKey: key)
    }
}
