//
//  ChatResult+Mock.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 20.03.2025.
//

import Foundation
@testable import OpenAI

extension ChatResult {
    static let mock = ChatResult(id: "id-12312", created: 100, model: .gpt3_5Turbo, object: "foo", serviceTier: nil, systemFingerprint: "fing", choices: [
        .init(index: 0, logprobs: nil, message: mockChatResultChoiceMessage(content: "bar", role: "system"), finishReason: "baz"),
        .init(index: 0, logprobs: nil, message: mockChatResultChoiceMessage(content: "bar1", role: "user"), finishReason: "baz1"),
        .init(index: 0, logprobs: nil, message: mockChatResultChoiceMessage(content: "bar2", role: "assistant"), finishReason: "baz2")
    ], usage: .init(completionTokens: 200, promptTokens: 100, totalTokens: 300, promptTokensDetails: nil), citations: nil)
    
    // The fork's tolerant init(from:) on Message (declared in the struct body, for `images`) removes
    // the memberwise initializer, so the mock message is decoded from JSON. // wangqi modified 2026-10-31
    static func mockChatResultChoiceMessage(
        content: String?,
        role: String,
        toolCalls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam] = []
    ) -> ChatResult.Choice.Message {
        // swiftlint:disable:next force_try
        let toolCallsJSON = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(toolCalls))
        var object: [String: Any] = ["role": role, "annotations": [Any](), "tool_calls": toolCallsJSON]
        if let content { object["content"] = content }
        // swiftlint:disable:next force_try
        let data = try! JSONSerialization.data(withJSONObject: object)
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(ChatResult.Choice.Message.self, from: data)
    }
}
