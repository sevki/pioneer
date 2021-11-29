//
//  AsyncEventStream.swift
//  Pioneer
//
//  Created by d-exclaimation on 3:17 PM.
//  Copyright © 2021 d-exclaimation. All rights reserved.
//

import GraphQL
import Desolate

/// EventStream implementation for AsyncSequence for allowing GraphQL Streaming.
public class AsyncEventStream<Element, Sequence: AsyncSequence>: EventStream<Element> where Sequence.Element == Element {
    /// Inner AsyncSequence
    public let sequence: Sequence

    public init(from: Sequence) {
        sequence = from
    }

    /// Override transforming method.
    ///
    /// - Parameter closure: Transformation closure.
    /// - Returns: A new EventStream with the new type.
    override open func map<To>(_ closure: @escaping (Element) throws -> To) -> EventStream<To> {
        /// Use AsyncStream as bridging instead of the built-in map function to allow for type casting
        /// as using `map` will make the type too complicated to be casted to any meaningful value
        /// Performance and efficiency has been tested to mostly not affected but do keep in mind to try to find a better solution.
        let stream = AsyncStream(To.self) { continuation in
            Task.init {
                do {
                    for try await each in self.sequence {
                        let res = try closure(each)
                        continuation.yield(res)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
        return AsyncEventStream<To, AsyncStream<To>>.init(from: stream)
    }
}



