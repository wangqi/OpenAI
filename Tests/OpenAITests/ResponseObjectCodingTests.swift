//
//  ResponseObjectCodingTests.swift
//  OpenAI
//

import Testing
@testable import OpenAI
import Foundation

// status is required by the fork's decoder (it must succeed or throw), so the fixtures carry it. // wangqi modified 2026-10-31
struct ResponseObjectCodingTests {
    private let minimalJSON = """
    {
        "id": "resp-abc123",
        "object": "response",
        "model": "gpt-4o",
        "created_at": 1717459200,
        "output": [],
        "tools": [],
        "metadata": {},
        "parallel_tool_calls": false,
        "status": "completed"
    }
    """

    @Test func decodeMinimalResponse() throws {
        let response = try decode(minimalJSON)
        #expect(response.id == "resp-abc123")
        #expect(response.object == "response")
        #expect(response.model == "gpt-4o")
        #expect(response.output.isEmpty)
        // tools is optional since the fork's tolerant decoding. // wangqi modified 2026-10-31
        #expect(response.tools?.isEmpty ?? true)
    }

    @Test func decodeCreatedAtAsDouble() throws {
        let response = try decode(minimalJSON)
        #expect(response.createdAt == 1717459200.0)
    }

    @Test func decodeIncompleteDetailsAbsent() throws {
        let response = try decode(minimalJSON)
        #expect(response.incompleteDetails == nil)
    }

    @Test func decodeIncompleteDetailsNull() throws {
        let json = """
        {
            "id": "resp-abc123",
            "object": "response",
            "model": "gpt-4o",
            "created_at": 1717459200,
            "output": [],
            "tools": [],
            "metadata": {},
            "parallel_tool_calls": false,
            "status": "incomplete",
            "incomplete_details": null
        }
        """
        let response = try decode(json)
        #expect(response.incompleteDetails == nil)
    }

    @Test func decodeIncompleteDetailsPresent() throws {
        let json = """
        {
            "id": "resp-abc123",
            "object": "response",
            "model": "gpt-4o",
            "created_at": 1717459200,
            "output": [],
            "tools": [],
            "metadata": {},
            "parallel_tool_calls": false,
            "status": "incomplete",
            "incomplete_details": { "reason": "max_output_tokens" }
        }
        """
        let response = try decode(json)
        #expect(response.incompleteDetails != nil)
    }

    private func decode(_ json: String) throws -> ResponseObject {
        try JSONDecoder().decode(ResponseObject.self, from: Data(json.utf8))
    }
}
