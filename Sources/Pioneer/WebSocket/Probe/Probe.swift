//
//  Probe.swift
//  Pioneer
//
//  Created by d-exclaimation on 11:32 PM.
//

import struct Foundation.UUID
import class Graphiti.Schema
import GraphQL
import protocol NIO.EventLoopGroup

extension Pioneer {
    /// Actor for handling Websocket distribution and dispatching of client specific actor
    actor Probe {
        private let schema: GraphQLSchema
        private let resolver: Resolver
        private let proto: SubProtocol.Type

        init(
            schema: GraphQLSchema, resolver: Resolver, proto: SubProtocol.Type
        ) {
            self.schema = schema
            self.resolver = resolver
            self.proto = proto
        }

        init(
            schema: Schema<Resolver, Context>, resolver: Resolver, proto: SubProtocol.Type
        ) {
            self.schema = schema.schema
            self.resolver = resolver
            self.proto = proto
        }

        // MARK: - Private mutable states

        private var clients: [UUID: WebSocketClient] = [:]
        private var drones: [UUID: Drone] = [:]

        // MARK: - Event callbacks

        /// Allocate space and save any verified process
        func connect(with client: WebSocketClient) async {
            clients.update(client.id, with: client)
        }

        /// Deallocate the space from a closing process
        func disconnect(for cid: UUID) async {
            await drones[cid]?.acid()
            clients.delete(cid)
            drones.delete(cid)
        }

        /// Long running operation require its own actor, thus initialing one if there were none prior
        func start(for cid: UUID, with oid: String, given gql: GraphQLRequest) async {
            guard let client = clients[cid] else {
                return
            }

            let drone = drones.getOrElse(cid) {
                .init(client,
                      schema: schema,
                      resolver: resolver,
                      proto: proto)
            }
            drones.update(cid, with: drone)
            await drone.start(for: oid, given: gql)
        }

        /// Short lived operation is processed immediately and pipe back later
        func once(for cid: UUID, with oid: String, given gql: GraphQLRequest) async {
            guard let client = clients[cid] else {
                return
            }

            let future = execute(gql, client: client)

            pipeToSelf(future: future) { sink, res in
                switch res {
                case let .success(value):
                    await sink.outgoing(
                        with: oid,
                        to: client,
                        given: .from(type: self.proto.next, id: oid, value)
                    )
                case let .failure(error):
                    let result: GraphQLResult = .init(data: nil, errors: [error.graphql])
                    await sink.outgoing(
                        with: oid,
                        to: client,
                        given: .from(type: self.proto.next, id: oid, result)
                    )
                }
            }
        }

        /// Stopping any operation to client specific actor
        func stop(for cid: UUID, with oid: String) async {
            await drones[cid]?.stop(for: oid)
        }

        /// Message for pipe to self result after processing short lived operation
        func outgoing(with oid: String, to client: WebSocketClient, given msg: GraphQLMessage) async {
            client.out(msg.jsonString)
            client.out(GraphQLMessage(id: oid, type: proto.complete).jsonString)
        }

        // MARK: - Utility methods

        /// Build context and execute short-lived GraphQL Operation inside an event loop
        private func execute(_ gql: GraphQLRequest, client: WebSocketClient) -> Task<GraphQLResult, Error> {
            Task { [unowned self] in
                let ctx = try await client.context(gql)
                return try await self.executeOperation(for: gql, with: ctx, using: client.ev)
            }
        }

        /// Execute short-lived GraphQL Operation
        private func executeOperation(for gql: GraphQLRequest, with ctx: Context, using eventLoop: EventLoopGroup) async throws -> GraphQLResult {
            try await executeGraphQL(
                schema: self.schema,
                request: gql.query,
                resolver: self.resolver,
                context: ctx,
                eventLoopGroup: eventLoop,
                variables: gql.variables,
                operationName: gql.operationName
            )
        }
    }
}
