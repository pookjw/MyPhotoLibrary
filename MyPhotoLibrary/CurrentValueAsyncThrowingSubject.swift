//
//  CurrentValueAsyncThrowingSubject.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/12/23.
//

import Foundation

actor CurrentValueAsyncThrowingSubject<Element: Sendable>: Equatable {
    static func == (lhs: CurrentValueAsyncThrowingSubject<Element>, rhs: CurrentValueAsyncThrowingSubject<Element>) -> Bool {
        lhs.uuid == rhs.uuid
    }
    
    private(set) var value: Element?
    private let uuid: UUID = .init()
    
    var stream: AsyncThrowingStream<Element, Error> {
        let (stream, continuation) = AsyncThrowingStream<Element, Error>.makeStream()
        let key = UUID()
        
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.remove(key: key)
            }
        }
        
        continuations[key] = continuation
        
        return stream
    }
    
    private var continuations: [UUID: AsyncThrowingStream<Element, Error>.Continuation] = .init()
    
    deinit {
        continuations.values.forEach { continuation in
            continuation.finish()
        }
    }
    
    func callAsFunction() -> AsyncThrowingStream<Element, Error> {
        stream
    }
    
    func yield(with result: Result<Element, Error>) {
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
