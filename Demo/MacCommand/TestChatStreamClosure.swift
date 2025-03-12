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
public func testChatStreamClosureTask(
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

    print("\nStart testChatStreamClosureTask test...\n")
    openAI.chatsStream(query: query) { partialResult in
        switch partialResult {
        case .success(let response):
            print("Response: \(response)")
            var content = response.choices.first?.delta.content ?? ""
            print("Content: \(content)")
        case .failure(let error):
            //Handle chunk error here
            print("failure: \(error)")
        }
    } completion: { error in
        //Handle streaming error here
        print("\nError:", error as Any)
    }

}
