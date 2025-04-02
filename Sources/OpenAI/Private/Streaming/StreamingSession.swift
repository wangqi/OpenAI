//
//  StreamingSession.swift
//
//
//  Created by Sergii Kryvoblotskyi on 18/04/2023.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class StreamingSession<Interpreter: StreamInterpreter>: NSObject, Identifiable, URLSessionDataDelegateProtocol, @unchecked Sendable {
    typealias ResultType = Interpreter.ResultType
    
    private let urlSessionFactory: URLSessionFactory
    private let urlRequest: URLRequest
    private let interpreter: Interpreter
    private let sslDelegate: SSLDelegateProtocol?
    // wangqi 2025-03-23
    private var onReceiveRawData: ((Data) -> Void)?
    private let middlewares: [OpenAIMiddleware]
    private let executionSerializer: ExecutionSerializer
    private let onReceiveContent: (@Sendable (StreamingSession, ResultType) -> Void)?
    private let onProcessingError: (@Sendable (StreamingSession, Error) -> Void)?
    private let onComplete: (@Sendable (StreamingSession, Error?) -> Void)?

    init(
        urlSessionFactory: URLSessionFactory = FoundationURLSessionFactory(),
        urlRequest: URLRequest,
        interpreter: Interpreter,
        sslDelegate: SSLDelegateProtocol?,
        middlewares: [OpenAIMiddleware],
        executionSerializer: ExecutionSerializer = GCDQueueAsyncExecutionSerializer(queue: .userInitiated),
        onReceiveContent: @escaping @Sendable (StreamingSession, ResultType) -> Void,
        onProcessingError: @escaping @Sendable (StreamingSession, Error) -> Void,
        onComplete: @escaping @Sendable (StreamingSession, Error?) -> Void
    ) {
        self.urlSessionFactory = urlSessionFactory
        self.urlRequest = urlRequest
        self.interpreter = interpreter
        self.sslDelegate = sslDelegate
        self.middlewares = middlewares
        self.executionSerializer = executionSerializer
        self.onReceiveContent = onReceiveContent
        self.onProcessingError = onProcessingError
        self.onComplete = onComplete
        super.init()
        subscribeToParser()
    }
    
    func makeSession() -> PerformableSession & InvalidatableSession {
        let urlSession = urlSessionFactory.makeUrlSession(delegate: self)
        return DataTaskPerformingURLSession(urlRequest: urlRequest, urlSession: urlSession)
    }
    
    func urlSession(_ session: any URLSessionProtocol, task: any URLSessionTaskProtocol, didCompleteWithError error: (any Error)?) {
        executionSerializer.dispatch {
            self.onComplete?(self,error)
        }
    }
    
    func urlSession(_ session: any URLSessionProtocol, dataTask: any URLSessionDataTaskProtocol, didReceive data: Data) {
        // Call the raw data callback if set
        // wangqi 2025-03-23
        onReceiveRawData?(data)
        executionSerializer.dispatch {
            let data = self.middlewares.reduce(data) { current, middleware in
                middleware.interceptStreamingData(request: dataTask.originalRequest, current)
            }
            
            self.interpreter.processData(data)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        executionSerializer.dispatch {
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                let error = OpenAIError.statusError(response: httpResponse, statusCode: httpResponse.statusCode)
                self.onProcessingError?(self, error)
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let sslDelegate else { return completionHandler(.performDefaultHandling, nil) }
        sslDelegate.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    private func subscribeToParser() {
        interpreter.setCallbackClosures { [weak self] content in
            guard let self else { return }
            self.onReceiveContent?(self, content)
        } onError: { [weak self] error in
            guard let self else { return }
            self.onProcessingError?(self, error)
        }
    }
}
