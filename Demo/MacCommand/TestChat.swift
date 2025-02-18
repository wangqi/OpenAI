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


/// Function to run the chat stream test
public func testChatTask(
    openAI: OpenAI,
    model: String,
    prompt: String,
    systemPrompt: String,
    repeatPenalty: Double,
    temperature: Double,
    topP: Double
) async {

    var chatMessages: [ChatQuery.ChatCompletionMessageParam] = []
    
    /*
    if !systemPrompt.isEmpty {
        chatMessages.append(.system(.init(content: systemPrompt)))
    }
     */

    chatMessages.append(.init(role: .user, content: prompt)!)

    let query = ChatQuery(
        messages: chatMessages,
        model: model,
        reasoningEffort: .low
        //presencePenalty: repeatPenalty,
        //temperature: temperature,
        //topP: topP
    )
    print("Setup query: \(query) for model: \(model)\n")

    print("\nStart testChatTask test...\n")
    do {
        let result = try await openAI.chats(query: query)
    } catch {
        print("error: \(error)")
    }

}
