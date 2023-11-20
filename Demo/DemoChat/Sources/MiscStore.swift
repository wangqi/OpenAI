//
//  MiscStore.swift
//  DemoChat
//
//  Created by Aled Samuel on 22/04/2023.
//

import UIKit
import OpenAI
import AVFAudio

public final class MiscStore: ObservableObject {
    public var openAIClient: OpenAIProtocol
    
    @Published var availableModels: [ModelResult] = []
    
    public init(
        openAIClient: OpenAIProtocol
    ) {
        self.openAIClient = openAIClient
    }
    
    // MARK: - Models
    
    @MainActor
    func getModels() async {
        do {
            let response = try await openAIClient.models()
            availableModels = response.data
        } catch {
            // TODO: Better error handling
            print(error.localizedDescription)
        }
    }
    
    // MARK: - Moderations
    
    @Published var moderationConversation = Conversation(id: "", messages: [])
    @Published var moderationConversationError: Error?
    
    @MainActor
    func sendModerationMessage(_ message: Message) async {
        moderationConversation.messages.append(message)
        await completeModerationChat(message: message)
    }
    
    @MainActor
    func completeModerationChat(message: Message) async {
        
        moderationConversationError = nil
        
        do {
            let response = try await openAIClient.moderations(
                query: ModerationsQuery(
                    input: message.content,
                    model: .textModerationLatest
                )
            )
            
            let categoryResults = response.results
            
            let existingMessages = moderationConversation.messages
            
            func circleEmoji(for resultType: Bool) -> String {
                resultType ? "🔴" : "🟢"
            }
            
            for result in categoryResults {
                let content = """
                \(circleEmoji(for: result.categories.hate)) Hate
                \(circleEmoji(for: result.categories.hateThreatening)) Hate/Threatening
                \(circleEmoji(for: result.categories.selfHarm)) Self-harm
                \(circleEmoji(for: result.categories.sexual)) Sexual
                \(circleEmoji(for: result.categories.sexualMinors)) Sexual/Minors
                \(circleEmoji(for: result.categories.violence)) Violence
                \(circleEmoji(for: result.categories.violenceGraphic)) Violence/Graphic
                """
                
                let message = Message(
                    id: response.id,
                    role: .assistant,
                    content: content,
                    createdAt: message.createdAt)
                
                if existingMessages.contains(message) {
                    continue
                }
                moderationConversation.messages.append(message)
            }
            
        } catch {
            moderationConversationError = error
        }
    }
    
    // MARK: - Speech
    struct AudioObject: Identifiable {
        let id = UUID()
        let prompt: String
        let audioPlayer: AVAudioPlayer?
        let originResponse: AudioSpeechResult
        let format: String
    }
    
    @Published var audioObjects: [AudioObject] = []
    
    @MainActor
    func createSpeech(_ query: AudioSpeechQuery) async {
        guard let input = query.input, !input.isEmpty else { return }
        do {
            let response = try await openAIClient.audioCreateSpeech(query: query)
            guard let data = response.audioData else { return }
            let player = try? AVAudioPlayer(data: data)
            let audioObject = AudioObject(prompt: input,
                                          audioPlayer: player,
                                          originResponse: response,
                                          format: query.responseFormat.rawValue)
            audioObjects.append(audioObject)
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func getFileInDocumentsDirectory(_ data: Data, fileName: String, _ dir: @escaping (URL) -> Void) {
        if let fileURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let saveURL = fileURL.appendingPathComponent(fileName)
            do {
                try data.write(to: saveURL)
                dir(saveURL)
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
}
