//
//  TestChatStream.swift
//  Demo
//
//  Created by Qi Wang on 2025-02-16.
//

//
//  TestChatStream.swift
//  MacCommand
//
//  Created by Qi Wang on 2025-02-16.
//

import Foundation
import Combine
import OpenAI

var testChatStreamSearchTask_cancellables = Set<AnyCancellable>()

/// Function to run the chat stream test
public func testChatStreamSearchTask(
    openAI: OpenAI,
    model: String,
    prompt: String,
    systemPrompt: String,
    repeatPenalty: Double,
    temperature: Double,
    topP: Double
) async {

    var chatMessages: [ChatQuery.ChatCompletionMessageParam] = []
    
    if !systemPrompt.isEmpty {
        chatMessages.append(.system(.init(content: systemPrompt)))
    }

    chatMessages.append(.init(role: .user, content: prompt)!)
    
    let searchFunction = ChatQuery.ChatCompletionToolParam(function: .init(
        name: "extract_data",
        description: "This function can get any data from the Internet. When you decide to query data and no other tools are suitable, use this function. Do not ask users to provide more tools",
        parameters: .init(
            type: .object,
            properties: [
                "keyword": .init(type: .string, description: "The keyword to be searched")
            ],
            required: ["keyword"]
        )
    ))

    let functions = [searchFunction]

    let query = ChatQuery(
        messages: chatMessages,
        model: model,
        presencePenalty: repeatPenalty,
        temperature: temperature,
        tools: functions,
        topP: topP,
        stream: true
    )
//    print("Setup query: \(query)")

    print("\nStart testChatStreamSearchTask test...\n")
    var totalTokens = 0
    var content = ""
    var totalDuration: Double = 0.0
    openAI.chatsStream(query: query)
        .sink { result in
            switch result {
            case .finished:
                print("\nChat stream completed.")
                print("Response: \(content)")
                print("duration: \(totalDuration), totalTokens: \(totalTokens)")
            case .failure(let error):
                print("\nError:", error)
            }
        } receiveValue: { response in
            // print("Response: \(response)")
            let now = Date().timeIntervalSince1970
            do {
                let result = try response.get()
                content += result.choices.first?.delta.content ?? ""
                if let finishReason = result.choices.first?.finishReason {
                    print("Result: ")
                    print(result)
                    print("Finish reason: \(finishReason)")
                }
                totalTokens += result.usage?.totalTokens ?? 0
            } catch {
                content = "Failed to get response: \(error)"
            }
            do {
                let createTime = try response.get().created
                totalDuration = now - createTime
            } catch {
                totalDuration = 0.0
            }
        }
        .store(in: &testChatStreamSearchTask_cancellables)
}
