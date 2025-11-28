//
//  ServerSentEventsStreamingSessionFactory.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 10.03.2025.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol StreamingSessionFactory: Sendable {
    func makeServerSentEventsStreamingSession<ResultType: Codable & Sendable>(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, ResultType) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, Error?) -> Void
    ) -> StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>
    
    func makeAudioSpeechStreamingSession(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, AudioSpeechResult) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, Error?) -> Void
    ) -> StreamingSession<AudioSpeechStreamInterpreter>
    
    func makeModelResponseStreamingSession(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, ResponseStreamEvent) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, Error?) -> Void
    ) -> StreamingSession<ModelResponseEventsStreamInterpreter>
}

struct ImplicitURLSessionStreamingSessionFactory: StreamingSessionFactory {
    let middlewares: [OpenAIMiddleware]
    let parsingOptions: ParsingOptions
    let sslDelegate: SSLDelegateProtocol?
    // wangqi 2025-11-28: Add custom URLSession factory for proxy support
    let urlSessionFactory: URLSessionFactory

    // wangqi 2025-11-28: Add initializer with default factory
    init(
        middlewares: [OpenAIMiddleware],
        parsingOptions: ParsingOptions,
        sslDelegate: SSLDelegateProtocol?,
        urlSessionFactory: URLSessionFactory = FoundationURLSessionFactory()
    ) {
        self.middlewares = middlewares
        self.parsingOptions = parsingOptions
        self.sslDelegate = sslDelegate
        self.urlSessionFactory = urlSessionFactory
    }

    func makeServerSentEventsStreamingSession<ResultType>(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, ResultType) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, any Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<ServerSentEventsStreamInterpreter<ResultType>>, (any Error)?) -> Void
    ) -> StreamingSession<ServerSentEventsStreamInterpreter<ResultType>> where ResultType : Decodable, ResultType : Encodable, ResultType : Sendable {
        .init(
            urlSessionFactory: urlSessionFactory,  // wangqi 2025-11-28: Pass custom factory
            urlRequest: urlRequest,
            interpreter: .init(parsingOptions: parsingOptions),
            sslDelegate: sslDelegate,
            middlewares: middlewares,
            onReceiveContent: onReceiveContent,
            onProcessingError: onProcessingError,
            onComplete: onComplete
        )
    }

    func makeAudioSpeechStreamingSession(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, AudioSpeechResult) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, any Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<AudioSpeechStreamInterpreter>, (any Error)?) -> Void
    ) -> StreamingSession<AudioSpeechStreamInterpreter> {
        .init(
            urlSessionFactory: urlSessionFactory,  // wangqi 2025-11-28: Pass custom factory
            urlRequest: urlRequest,
            interpreter: .init(),
            sslDelegate: sslDelegate,
            middlewares: middlewares,
            onReceiveContent: onReceiveContent,
            onProcessingError: onProcessingError,
            onComplete: onComplete
        )
    }

    func makeModelResponseStreamingSession(
        urlRequest: URLRequest,
        onReceiveContent: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, ResponseStreamEvent) -> Void,
        onProcessingError: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, any Error) -> Void,
        onComplete: @Sendable @escaping (StreamingSession<ModelResponseEventsStreamInterpreter>, (any Error)?) -> Void
    ) -> StreamingSession<ModelResponseEventsStreamInterpreter> {
        .init(
            urlSessionFactory: urlSessionFactory,  // wangqi 2025-11-28: Pass custom factory
            urlRequest: urlRequest,
            interpreter: .init(),
            sslDelegate: sslDelegate,
            middlewares: middlewares,
            onReceiveContent: onReceiveContent,
            onProcessingError: onProcessingError,
            onComplete: onComplete
        )
    }
}
