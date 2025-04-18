//
//  OpenAIMiddlewareImpl.swift
//  OpenAI
//
//  Created by Qi Wang on 2025-04-18.
//


import Foundation

public final class OpenAIMiddlewareImpl: OpenAIMiddleware {
    private let label: String
    private let debugHandler: ((String) -> Void)?

    public init(label: String = "OpenAI Inspector", debugHandler: ((String) -> Void)? = nil) {
        self.label = label
        self.debugHandler = debugHandler
    }

    public func intercept(request: URLRequest) -> URLRequest {
        var output = "\n\n[\(label)] Outgoing Request:\n"

        if let method = request.httpMethod {
            output += "Method: \(method)\n"
        }

        output += "URL: \(request.url?.absoluteString ?? "<unknown URL>")\n"
        output += "Headers:\n"
        request.allHTTPHeaderFields?.forEach { key, value in
            output += "  \(key): \(value)\n"
        }

        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            output += "Body:\n\(prettyPrintJSON(from: bodyString) ?? bodyString)\n"
        } else {
            output += "Body: <empty or binary>\n"
        }

        emit(output)
        return request
    }

    public func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data {
        guard let string = String(data: data, encoding: .utf8) else {
            emit("[\(label)] Streaming Data: <non-UTF8 binary>")
            return data
        }

        for line in string.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            emit("[\(label)] Streaming Line: \(line)")
        }

        return data
    }

    public func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) {
        var output = "\n\n[\(label)] Response:\n"

        if let httpResponse = response as? HTTPURLResponse {
            output += "Status Code: \(httpResponse.statusCode)\n"
            output += "URL: \(httpResponse.url?.absoluteString ?? "<unknown URL>")\n"
            output += "Headers:\n"
            for (key, value) in httpResponse.allHeaderFields {
                output += "  \(key): \(value)\n"
            }
        }

        if let data = data {
            if let jsonString = String(data: data, encoding: .utf8) {
                output += "Body:\n\(prettyPrintJSON(from: jsonString) ?? jsonString)\n"
            } else {
                output += "Body: <non-UTF8 binary>\n"
            }
        } else {
            output += "Body: <no data>\n"
        }

        emit(output)
        return (response, data)
    }

    // MARK: - Utilities

    private func emit(_ message: String) {
        if let handler = debugHandler {
            handler(message)
        } else {
            print(message)
        }
    }

    private func prettyPrintJSON(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }

        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
            return String(data: prettyData, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
