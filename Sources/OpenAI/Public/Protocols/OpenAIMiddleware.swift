import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol OpenAIMiddleware: Sendable {
    func intercept(request: URLRequest) -> URLRequest
    func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data
    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?)
    // wangqi modified 2025-05-20
    func interceptError(response: URLResponse?, request: URLRequest?, data: Data?, error: Error?)
}

public extension OpenAIMiddleware {
    func intercept(request: URLRequest) -> URLRequest { request }
    func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data { data }
    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) { (response, data) }
    // wangqi modified 2025-05-20
    func interceptError(response: URLResponse?, request: URLRequest?, data: Data?, error: Error?) -> Void {}
}
