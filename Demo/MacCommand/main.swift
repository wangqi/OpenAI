//
//  main.swift
//  MacCommand
//
//  Created by Qi Wang on 2025-02-16.
//

import Foundation
import OpenAI

// Retrieve the token from the environment
guard let token = ProcessInfo.processInfo.environment["OPENAI_API_TOKEN"], !token.isEmpty else {
    fatalError("Missing API Token. Set OPENAI_API_TOKEN in your environment.")
}

// Parameters
let repeat_penalty: Double = 1.1
let temp: Double = 0.7
let topP = 0.9
// let model = "gpt-4o-mini"
let model = "o3-mini"
let system_prompt = "You are a friendly AI assistant."

let configuration = OpenAI.Configuration(token: token, organizationIdentifier: "", timeoutInterval: 60.0)
let openAI = OpenAI(configuration: configuration)
print("Connect to OpenAI")

let prompt = "Using the numbers [19, 36, 55, 7], create an equation that equals 65."

// Interactive user input loop
func startInteractiveLoop() {
    while true {
        print("\nEnter '1' to run the chat task, or '0' to exit:")
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            continue
        }

        switch input {
        case "1":
            Task {
                await testChatStreamTask(
                    openAI: openAI,
                    model: model,
                    prompt: prompt,
                    systemPrompt: system_prompt,
                    repeatPenalty: repeat_penalty,
                    temperature: temp,
                    topP: topP
                )
            }
        case "2":
            Task {
                await testChatStreamClosureTask(
                    openAI: openAI,
                    model: model,
                    prompt: prompt,
                    systemPrompt: system_prompt,
                    repeatPenalty: repeat_penalty,
                    temperature: temp,
                    topP: topP
                )
            }
        case "3":
            Task {
                await testChatTask(
                    openAI: openAI,
                    model: model,
                    prompt: prompt,
                    systemPrompt: system_prompt,
                    repeatPenalty: repeat_penalty,
                    temperature: temp,
                    topP: topP
                )
            }
        case "0":
            print("Exiting...")
            exit(0)
        default:
            print("Invalid input. Please enter '1' to run or '0' to exit.")
        }
    }
}

// Start the interactive loop
startInteractiveLoop()
