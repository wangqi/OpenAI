//
//  AsyncClient.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 28.03.2025.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor AsyncClient {
    private let configuration: OpenAI.Configuration
    private let middlewares: [OpenAIMiddleware]
    private let session: URLSessionProtocol
    private let dataTaskFactory: DataTaskFactory
    private let responseHandler: URLResponseHandler
    
    init(
        configuration: OpenAI.Configuration,
        middlewares: [OpenAIMiddleware],
        session: URLSessionProtocol,
        dataTaskFactory: DataTaskFactory,
        responseHandler: URLResponseHandler
    ) {
        self.configuration = configuration
        self.middlewares = middlewares
        self.session = session
        self.dataTaskFactory = dataTaskFactory
        self.responseHandler = responseHandler
    }
    
    func performRequest<ResultType: Codable & Sendable>(request: any URLRequestBuildable) async throws -> ResultType {
        let urlRequest = try request.build(configuration: configuration)
        let interceptedRequest = middlewares.reduce(urlRequest) { current, middleware in
            middleware.intercept(request: current)
        }

        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            let (data, response) = try await session.data(for: interceptedRequest, delegate: nil)
            do {
                return try responseHandler.interceptAndDecode(response: response, urlRequest: urlRequest, responseData: data)
            } catch {
                //wangqi 2025-04-18
                let jsonString = String(data: data, encoding: .utf8) ?? ""
                print("Error response: \(error)")
                print("JSON: \(jsonString)")
                throw error
            }
        } else {
            let dataTaskStore = URLSessionDataTaskStore()
            return try await withTaskCancellationHandler {
                return try await withCheckedThrowingContinuation { continuation in
                    let dataTask = self.makeDataTask(forRequest: interceptedRequest) { (result: Result<ResultType, Error>) in
                        continuation.resume(with: result)
                    }
                    
                    dataTask.resume()
                    
                    Task {
                        await dataTaskStore.setDataTask(dataTask)
                    }
                }
            } onCancel: {
                Task {
                    await dataTaskStore.getDataTask()?.cancel()
                }
            }
        }
    }
    
    func performSpeechRequestAsync(request: any URLRequestBuildable) async throws -> AudioSpeechResult {
        let urlRequest = try request.build(configuration: configuration)
        let interceptedRequest = middlewares.reduce(urlRequest) { current, middleware in
            middleware.intercept(request: current)
        }
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            let (data, response) = try await session.data(for: interceptedRequest, delegate: nil)
            let finalData = try responseHandler.interceptAndDecodeRaw(response: response, urlRequest: urlRequest, responseData: data)
            return .init(audio: finalData)
        } else {
            let dataTaskStore = URLSessionDataTaskStore()
            return try await withTaskCancellationHandler {
                return try await withCheckedThrowingContinuation { continuation in
                    let dataTask = self.dataTaskFactory.makeRawResponseDataTask(forRequest: interceptedRequest) { result in
                        switch result {
                        case .success(let success):
                            continuation.resume(returning: .init(audio: success))
                        case .failure(let failure):
                            continuation.resume(throwing: failure)
                        }
                    }
                    
                    dataTask.resume()
                    
                    Task {
                        await dataTaskStore.setDataTask(dataTask)
                    }
                }
            } onCancel: {
                Task {
                    await dataTaskStore.getDataTask()?.cancel()
                }
            }
        }
    }
    
    private func makeDataTask<ResultType: Codable>(
        forRequest request: URLRequest,
        completion: @escaping @Sendable (Result<ResultType, Error>) -> Void
    ) -> URLSessionDataTaskProtocol {
        dataTaskFactory.makeDataTask(forRequest: request, completion: completion)
    }
}
