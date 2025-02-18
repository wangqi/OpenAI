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

var cancellables = Set<AnyCancellable>()

/// Function to run the chat stream test
public func testChatStreamTask(
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

    let query = ChatQuery(
        messages: chatMessages,
        model: model,
        presencePenalty: repeatPenalty,
        temperature: temperature,
        topP: topP,
        stream: true
    )
    print("Setup query: \(query)")

    print("\nStart testChatStreamTask test...\n")
    openAI.chatsStream(query: query)
        .sink { result in
            switch result {
            case .finished:
                print("\nChat stream completed.")
            case .failure(let error):
                print("\nError:", error)
            }
        } receiveValue: { response in
            print("Response: \(response)")
            let now = Date().timeIntervalSince1970
            var content = ""
            var totalDuration: Double = 0.0
            do {
                content = try response.get().choices.first?.delta.content ?? ""
            } catch {
                content = "Failed to get response: \(error)"
            }
            do {
                let createTime = try response.get().created
                totalDuration = now - createTime
            } catch {
                totalDuration = 0.0
            }
            print("Response: \(content), duration: \(totalDuration)")
        }
        .store(in: &cancellables)
}
