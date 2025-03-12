//
//  main.swift
//  MacCommand
//
//  Created by Qi Wang on 2025-02-16.
//

import Foundation
import OpenAI

// Provider configuration structure
struct Provider: Codable {
    let name: String
    let apiKey: String
    let scheme: String
    let host: String
    let port: Int
    let basePath: String
    let defaultModel: String
    let organizationId: String
}

struct ProvidersConfig: Codable {
    let providers: [Provider]
}

// Load providers from JSON configuration file
func loadProviders() -> [Provider] {
    let currentDirectory = FileManager.default.currentDirectoryPath
    print("Current directory: \(currentDirectory)")
    
    // Try to use an absolute path if the file can't be found in the current directory
    let fileURL = URL(fileURLWithPath: currentDirectory)
        .appendingPathComponent("providers.json")
    
    let absolutePath = "/Users/wangqi/disk/projects/ai/providers.json"
    let absoluteURL = URL(fileURLWithPath: absolutePath)
    
    do {
        // First try with the current directory path
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let config = try JSONDecoder().decode(ProvidersConfig.self, from: data)
            return config.providers
        } else {
            // If not found, try with the absolute path
            print("Using absolute path: \(absolutePath)")
            let data = try Data(contentsOf: absoluteURL)
            let config = try JSONDecoder().decode(ProvidersConfig.self, from: data)
            return config.providers
        }
    } catch {
        print("Error loading providers configuration: \(error)")
        return []
    }
}

// Display available providers and let user select one
func selectProvider(providers: [Provider]) -> Provider? {
    print("\nAvailable AI Service Providers:")
    for (index, provider) in providers.enumerated() {
        print("\(index + 1). \(provider.name)")
    }
    
    print("\nEnter the number of the provider you want to use:")
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
          let selection = Int(input),
          selection > 0 && selection <= providers.count else {
        print("Invalid selection.")
        return nil
    }
    
    return providers[selection - 1]
}

// Function to change the model
func changeModel() -> String {
    print("\nEnter the name of the model you want to use:")
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
        print("Invalid model name.")
        return ""
    }
    return input
}

// Function to change the prompt
func changePrompt() -> String {
    print("\nEnter the new prompt:")
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
        print("Invalid prompt.")
        return ""
    }
    return input
}

// Function to change the system prompt
func changeSystemPrompt() -> String {
    print("\nEnter the new system prompt:")
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
        print("Invalid system prompt.")
        return ""
    }
    return input
}

// Parameters
let repeat_penalty: Double = 1.1
let temp: Double = 0.7
let topP = 0.9
let system_prompt = "You are a friendly AI assistant."

// Load providers from configuration file
let providers = loadProviders()
guard !providers.isEmpty else {
    fatalError("No providers found in configuration file.")
}

// Let user select a provider
guard let selectedProvider = selectProvider(providers: providers) else {
    fatalError("Provider selection failed.")
}

print("Selected provider: \(selectedProvider.name)")
let model = selectedProvider.defaultModel

// Initialize OpenAI with the selected provider's configuration
let configuration = OpenAI.Configuration(
    token: selectedProvider.apiKey,
    host: selectedProvider.host,
    port: selectedProvider.port,
    scheme: selectedProvider.scheme,
    basePath: selectedProvider.basePath
)
let openAI = OpenAI(configuration: configuration)
print("Connected to \(selectedProvider.name). host: \(selectedProvider.host), port: \(selectedProvider.port), scheme: \(selectedProvider.scheme), basePath: \(selectedProvider.basePath)")

//let prompt = "Tell me the latest stock price for QQQ"
let prompt = """
模拟战争策略游戏，玩家养成多支弓步骑队伍，玩家攻城推进主要以公会成员的合作为基础，战斗方式以玩家指挥一支或多支队伍的微操为战斗玩法，请给出玩家指挥、操作多支队伍并与公会其他队友合作与敌对公会对抗的最佳游戏规则、赛季目标、大地图策略和养成方式
"""

let console_help = """
Please enter 
'1' to run chat stream, 
'2' for stream closure, 
'3' for chat, 
'4' to list models,
'5' to change model, 
'6' to change prompt, 
'7' to change system prompt, 
'8' to run chat stream search, 
or '0' to exit.")
"""

// Interactive user input loop
print(console_help)
func startInteractiveLoop() {
    var currentModel = model
    var currentPrompt = prompt
    var currentSystemPrompt = system_prompt
    
    while true {
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            continue
        }
        print("> \(input)")

        switch input {
        case "1":
            Task {
                await testChatStreamTask(
                    openAI: openAI,
                    model: currentModel,
                    prompt: currentPrompt,
                    systemPrompt: currentSystemPrompt,
                    repeatPenalty: repeat_penalty,
                    temperature: temp,
                    topP: topP
                )
            }
        case "2":
            Task {
                await testChatStreamClosureTask(
                    openAI: openAI,
                    model: currentModel,
                    prompt: currentPrompt,
                    systemPrompt: currentSystemPrompt,
                    repeatPenalty: repeat_penalty,
                    temperature: temp,
                    topP: topP
                )
            }
        case "3":
            Task {
                await testChatTask(
                    openAI: openAI,
                    model: currentModel,
                    prompt: currentPrompt,
                    systemPrompt: currentSystemPrompt,
                    repeatPenalty: repeat_penalty,
                    temperature: temp,
                    topP: topP
                )
            }
        case "4":
            Task {
                openAI.models { result in
                    do {
                        let modelList = try result.get().data
                        print("Model list: \n\(modelList)")
                    } catch {
                        print("Failed to fetch model list: \(error)")
                    }
                }
            }
        case "5":
            let newModel = changeModel()
            if !newModel.isEmpty {
                currentModel = newModel
                print("Model changed to: \(currentModel)")
            }
        case "6":
            let newPrompt = changePrompt()
            if !newPrompt.isEmpty {
                currentPrompt = newPrompt
                print("Prompt changed to: \(currentPrompt)")
            }
        case "7":
            let newSystemPrompt = changeSystemPrompt()
            if !newSystemPrompt.isEmpty {
                currentSystemPrompt = newSystemPrompt
                print("System prompt changed to: \(currentSystemPrompt)")
            }
        case "8":
            Task {
                await testChatStreamSearchTask(
                    openAI: openAI,
                    model: currentModel,
                    prompt: currentPrompt,
                    systemPrompt: currentSystemPrompt,
                    repeatPenalty: repeat_penalty,
                    temperature: temp,
                    topP: topP
                )
            }
        case "0":
            print("Exiting...")
            exit(0)
        default:
            print(console_help)
        }
    }
}

// Start the interactive loop
startInteractiveLoop()
