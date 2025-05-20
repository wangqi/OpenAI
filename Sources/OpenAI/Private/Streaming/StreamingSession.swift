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
    // wangqi modified 2025-05-20
    private var responseData: Data?
    // Add a flag to track error response state
    private var isCollectingErrorResponse: Bool = false

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
    
    // Compelete rewrite this function to return error
    // wangqi modified 2025-05-20
    func urlSession(_ session: any URLSessionProtocol, task: any URLSessionTaskProtocol, didCompleteWithError error: (any Error)?) {
        executionSerializer.dispatch {
            // --- Try to get the HTTPURLResponse if possible
            var httpResponse: HTTPURLResponse?
            var urlResponse: URLResponse?

            // If the real object is a URLSessionTask, get .response
            if let realTask = task as? URLSessionTask {
                urlResponse = realTask.response
                httpResponse = realTask.response as? HTTPURLResponse
            }

            let statusCode = httpResponse?.statusCode ?? 0
            let isHTTPError = statusCode >= 400
            
            var finalError: Error? = error
            defer { self.onComplete?(self, finalError) }

            if self.isCollectingErrorResponse || isHTTPError {
                for middleware in self.middlewares {
                    if let openAIMiddleware = middleware as? OpenAIMiddlewareImpl {
                        openAIMiddleware.interceptError(
                            response: urlResponse, // <-- FIXED: use urlResponse here
                            request: task.originalRequest,
                            data: self.responseData,
                            error: error
                        )
                    }
                }

                if let httpResponse = httpResponse {
                    let errorBody = String(data: self.responseData ?? Data(), encoding: .utf8) ?? ""
                    let composedError = NSError(
                        domain: "HTTPError",
                        code: statusCode,
                        userInfo: [
                            NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: statusCode),
                            NSDebugDescriptionErrorKey: errorBody,
                            "HTTPResponse": httpResponse
                        ]
                    )
                    self.onProcessingError?(self, composedError)
                    finalError = composedError
                } else if let error = error {
                    self.onProcessingError?(self, error)
                    finalError = error
                } else {
                    let unknownError = NSError(domain: "UnknownNetworkError", code: -1, userInfo: nil)
                    self.onProcessingError?(self, unknownError)
                    finalError = unknownError
                }

                self.isCollectingErrorResponse = false
                self.responseData = nil
                return
            }

            self.responseData = nil
            self.isCollectingErrorResponse = false
        }
    }
    
    func urlSession(_ session: any URLSessionProtocol, dataTask: any URLSessionDataTaskProtocol, didReceive data: Data) {
        // Call the raw data callback if set
        // wangqi 2025-03-23
        onReceiveRawData?(data)
        // Accumulate response data for error handling
        // wangqi modified 2025-05-20
        if responseData == nil {
            responseData = Data()
        }
        responseData?.append(data)
        
        executionSerializer.dispatch {
            let data = self.middlewares.reduce(data) { current, middleware in
                middleware.interceptStreamingData(request: dataTask.originalRequest, current)
            }
            
            self.interpreter.processData(data)
        }
    }

    func urlSession(
        _ session: URLSessionProtocol,
        dataTask: URLSessionDataTaskProtocol,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        executionSerializer.dispatch {
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                /*
                 let error = OpenAIError.statusError(response: httpResponse, statusCode: httpResponse.statusCode)
                 self.onProcessingError?(self, error)
                 completionHandler(.cancel)
                 return
                 */
                // wangqi modified 2025-05-20
                // Enter error response collecting mode, but DO NOT cancel immediately!
                self.isCollectingErrorResponse = true
                // Reset response data to start collecting error response
                self.responseData = Data()
                // Let the server finish sending the error body. We'll handle error in didCompleteWithError.
                completionHandler(.allow) // <-- Key change: allow streaming to finish so we get the body!
                return
            }
            // --- CHANGE: For non-error responses, turn off error collection and reset responseData
            self.isCollectingErrorResponse = false
            self.responseData = nil
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
