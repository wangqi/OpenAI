//
//  ResponseObject+Mock.swift
//  OpenAI
//

import Foundation
@testable import OpenAI

extension ResponseObject {
    // The fork's tolerant init(from:) (declared in the struct body) removes the memberwise
    // initializer, and `status` is a String since the 2026-06-11 upstream merge, so the mock is
    // built by decoding JSON through the real decoder. // wangqi modified 2026-10-31
    static func makeMock(
        output: [OutputItem] = [],
        tools: [Tool] = [],
        status: String = "completed"
    ) -> ResponseObject {
        let encoder = JSONEncoder()
        func jsonValue<T: Encodable>(_ value: T) -> Any {
            // swiftlint:disable:next force_try
            try! JSONSerialization.jsonObject(with: encoder.encode(value))
        }
        let object: [String: Any] = [
            "created_at": 123,
            "id": "resp-1",
            "metadata": [String: String](),
            "model": "test-model",
            "object": "response",
            "output": jsonValue(output),
            "parallel_tool_calls": false,
            "status": status,
            "text": [String: Any](),
            "tool_choice": "auto",
            "tools": jsonValue(tools),
        ]
        // swiftlint:disable:next force_try
        let data = try! JSONSerialization.data(withJSONObject: object)
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(ResponseObject.self, from: data)
    }
}
