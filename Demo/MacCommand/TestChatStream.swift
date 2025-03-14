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
    var totalTokens = 0
    var content = ""
    var totalDuration: Double = 0.0
    let semaphore = DispatchSemaphore(value: 0) // ✅ Prevents early exit
    var cancellables = Set<AnyCancellable>() // ✅ Prevents premature deallocation

    await withCheckedContinuation { continuation in
        openAI.chatsStream(query: query)
            .sink { result in
                switch result {
                case .finished:
                    print("\nChat stream completed.")
                    print("Response: \(content)")
                    print("duration: \(totalDuration), totalTokens: \(totalTokens)")
                    continuation.resume()  // ✅ Ensures proper completion
                    semaphore.signal()      // ✅ Unblocks thread
                case .failure(let error):
                    print("\nError:", error)
                    continuation.resume()  // ✅ Ensures proper completion even on failure
                    semaphore.signal()      // ✅ Unblocks thread
                }
            } receiveValue: { response in
                let now = Date().timeIntervalSince1970
                do {
                    let result = try response.get()
                    content += result.choices.first?.delta.content ?? ""
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
            .store(in: &cancellables)

        // ✅ Wait for stream completion to prevent premature deallocation
        semaphore.wait()
    }
        
}
