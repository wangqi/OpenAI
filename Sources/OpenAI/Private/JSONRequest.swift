//
//  JSONRequest.swift
//  
//
//  Created by Sergii Kryvoblotskyi on 12/19/22.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class JSONRequest<ResultType> {
    
    let body: (Codable & Sendable)?
    let url: URL
    let method: String
    
    init(body: (Codable & Sendable)? = nil, url: URL, method: String = "POST", customHeaders: [String: String] = [:]) {
        self.body = body
        self.url = url
        self.method = method
    }
}

extension JSONRequest: URLRequestBuildable {
    func build(
        token: String?,
        organizationIdentifier: String?,
        timeoutInterval: TimeInterval,
        customHeaders: [String: String]
    ) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token {        
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let organizationIdentifier {
            request.setValue(organizationIdentifier, forHTTPHeaderField: "OpenAI-Organization")
        }
        
        for (headerField, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: headerField)
        }
        
        request.httpMethod = method
        if let body = body {
            // Deterministic key order for the whole request body.
            //
            // `JSONEncoder` does NOT preserve the order a `Codable` type writes its keys in — a
            // custom `encode(to:)` cannot control it, and without `.sortedKeys` the same query
            // serializes to different bytes on different calls. The `tools` block alone runs to
            // ~17,000 tokens and is re-sent on every request of an agent run, so a provider that
            // compares `system -> tools -> messages` in order loses its cached prefix before it
            // reaches the message list. JSON object key order is semantically insignificant, so
            // this is behaviour-neutral. Array order is untouched (and is why `required` is sorted
            // at the converter in ToolParameter.swift instead).
            // wangqi modified 2026-07-28
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            request.httpBody = try encoder.encode(body)
        }
        return request
    }
}
