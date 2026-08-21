//
//  OpenAIMiddlewareImpl.swift
//  OpenAI
//
//  Created by Qi Wang on 2025-04-18.
//


import Foundation

public final class OpenAIMiddlewareImpl: OpenAIMiddleware {
    private let label: String
    private let debugHandler: ((String, String) -> Void)?

    // This middleware wrote every request header verbatim, so a capture held
    // "Authorization: Bearer <live key>" once per request -- 48 times in a single
    // 21 MB log that lands in the working directory and is shared whenever a log
    // is shared. The app already has a masker (StringUtil.maskedHeaderValue) and
    // three other inspectors already use it; this one was missed because an SPM
    // module cannot import the app's StringUtil.
    //
    // So the masker is INJECTED rather than reimplemented here: the app passes
    // its own, and there is still exactly one masking implementation in the
    // project. `(headerName, headerValue) -> displayValue`.
    // wangqi modified 2026-08-20
    private let headerMasker: (String, String) -> String

    // Fail-safe used when no masker is injected. Deliberately blunter than the
    // app's -- it redacts outright rather than keeping a diagnosable prefix --
    // because the only thing worse than a coarse mask is a default that leaks.
    // A future call site that forgets `headerMasker:` loses readability, not the
    // key. wangqi modified 2026-08-20
    private static func defaultMask(_ name: String, _ value: String) -> String {
        let n = name.lowercased()
        let sensitive = n.contains("auth") || n.contains("key")
                     || n.contains("token") || n.contains("cookie")
        return sensitive ? "<redacted>" : value
    }

    // `headerMasker` is placed BEFORE `debugHandler` on purpose: every existing
    // call site passes `debugHandler` as a trailing closure, and a trailing
    // closure binds to the LAST parameter. wangqi modified 2026-08-20
    public init(label: String = "OpenAI Inspector",
                headerMasker: ((String, String) -> String)? = nil,
                debugHandler: ((String, String) -> Void)? = nil) {
        self.label = label
        self.headerMasker = headerMasker ?? OpenAIMiddlewareImpl.defaultMask
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
            // The leak. `Authorization: Bearer <live key>`, verbatim, once per
            // request. wangqi modified 2026-08-20
            output += "  \(key): \(headerMasker(key, value))\n"
        }

        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            output += "Body:\n\(prettyPrintJSON(from: bodyString) ?? bodyString)\n"
        } else {
            output += "Body: <empty or binary>\n"
        }

        emit(output, type: "request")
        return request
    }

    public func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data {
        guard let string = String(data: data, encoding: .utf8) else {
            emit("[\(label)] Streaming Data: <non-UTF8 binary>", type: "streaming")
            return data
        }

        for line in string.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            emit("[\(label)] Streaming Line: \(line)", type: "streaming")
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
                // Lower risk than a request Authorization, but Set-Cookie passes
                // through here. wangqi modified 2026-08-20
                let name = "\(key)"
                output += "  \(key): \(headerMasker(name, "\(value)"))\n"
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

        emit(output, type: "response")
        return (response, data)
    }

    // wangqi modified 2025-05-20
    public func interceptError(response: URLResponse?, request: URLRequest?, data: Data?, error: Error?) {
        var output = "\n\n[\(label)] Response Error Intercepted:\n"
        
        // Print HTTPURLResponse details
        if let httpResponse = response as? HTTPURLResponse {
            output += "Status Code: \(httpResponse.statusCode)\n"
            output += "URL: \(httpResponse.url?.absoluteString ?? "<unknown URL>")\n"
            output += "Headers:\n"
            for (key, value) in httpResponse.allHeaderFields {
                // Lower risk than a request Authorization, but Set-Cookie passes
                // through here. wangqi modified 2026-08-20
                let name = "\(key)"
                output += "  \(key): \(headerMasker(name, "\(value)"))\n"
            }
        } else if let response = response {
            output += "Response: \(response)\n"
        } else {
            output += "Response: <none>\n"
        }

        // Print error body if available
        if let data = data, !data.isEmpty {
            if let jsonString = String(data: data, encoding: .utf8) {
                output += "Body:\n\(prettyPrintJSON(from: jsonString) ?? jsonString)\n"
            } else {
                output += "Body: <non-UTF8 binary>\n"
            }
        } else {
            output += "Body: <no data>\n"
        }
        
        // Print Error if present
        if let error = error {
            output += "Error: \(error)\n"
            if let nsError = error as NSError? {
                if let failingURL = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
                    output += "Failing URL: \(failingURL)\n"
                }
                if let responseData = nsError.userInfo["com.alamofire.serialization.response.error.data"] as? Data, // Alamofire-specific
                   let errorString = String(data: responseData, encoding: .utf8) {
                    output += "Alamofire Error Data:\n\(prettyPrintJSON(from: errorString) ?? errorString)\n"
                }
                // Dump all userInfo
                if !nsError.userInfo.isEmpty {
                    output += "NSError.userInfo:\n"
                    for (key, value) in nsError.userInfo {
                        // URLSession puts the failing NSURLRequest in here, and
                        // its description carries the headers with it. Masked by
                        // key name for the same reason as above.
                        // wangqi modified 2026-08-20
                        output += "  \(key): \(headerMasker(key, "\(value)"))\n"
                    }
                }
            }
        } else {
            output += "Error: <none>\n"
        }
        
        emit(output, type: "error")
    }

    // MARK: - Utilities

    private func emit(_ message: String, type: String) {
        if let handler = debugHandler {
            handler(message, type)
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
