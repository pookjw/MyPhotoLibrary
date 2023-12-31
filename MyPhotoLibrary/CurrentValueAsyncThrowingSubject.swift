//
//  CurrentValueAsyncThrowingSubject.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/12/23.
//

import Foundation

@MainActor
final class CurrentValueAsyncThrowingSubject<Element: Sendable>: Equatable {
    static nonisolated func == (lhs: CurrentValueAsyncThrowingSubject<Element>, rhs: CurrentValueAsyncThrowingSubject<Element>) -> Bool {
        lhs.uuid == rhs.uuid
    }
    
    private(set) var value: Element?
    private(set) var isFinished: Bool = false
    
    private var finishHandler: (@Sendable @MainActor () -> Void)?
    private let uuid: UUID = .init()
    
    var stream: AsyncThrowingStream<Element, Error> {
        assert(!isFinished)
        
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
    
    init(value: Element? = nil) {
        self.value = value
    }
    
    deinit {
        continuations.values.forEach { continuation in
            continuation.finish()
        }
    }
    
    func callAsFunction() -> AsyncThrowingStream<Element, Error> {
        stream
    }
    
    func yield(with result: Result<Element, Error>) {
        assert(!isFinished)
        
        if case .success(let newValue) = result {
            value = newValue
        }
        
        continuations.values.forEach { continuation in
            continuation.yield(with: result)
        }
    }
    
    func yield(_ value: Element) {
        assert(!isFinished)
        
        self.value = value
        
        continuations.values.forEach { continuation in
            continuation.yield(value)
        }
    }
    
    func finish() {
        guard !isFinished else {
            return
        }
        
        isFinished = true
        finishHandler?()
        finishHandler = nil
    }
    
    func setFinishHandler(_ finishHandler: @escaping @Sendable @MainActor () -> Void) {
        self.finishHandler = finishHandler
    }
    
    private func remove(key: UUID) {
        continuations.removeValue(forKey: key)
    }
}
