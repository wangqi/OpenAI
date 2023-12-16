//
//  ChatStore.swift
//  DemoChat
//
//  Created by Sihao Lu on 3/25/23.
//

import Foundation
import Combine
import OpenAI
import SwiftUI

public final class ChatStore: ObservableObject {
    public var openAIClient: OpenAIProtocol
    let idProvider: () -> String

    @Published var conversations: [Conversation] = []
    @Published var conversationErrors: [Conversation.ID: Error] = [:]
    @Published var selectedConversationID: Conversation.ID?

    // Used for assistants API state.
    private var timer: Timer?
    private var timeInterval: TimeInterval = 1.0
    private var currentRunId: String?
    private var currentThreadId: String?
    private var currentConversationId: String?

    @Published var isSendingMessage = false

    var selectedConversation: Conversation? {
        selectedConversationID.flatMap { id in
            conversations.first { $0.id == id }
        }
    }

    var selectedConversationPublisher: AnyPublisher<Conversation?, Never> {
        $selectedConversationID.receive(on: RunLoop.main).map { id in
            self.conversations.first(where: { $0.id == id })
        }
        .eraseToAnyPublisher()
    }

    public init(
        openAIClient: OpenAIProtocol,
        idProvider: @escaping () -> String
    ) {
        self.openAIClient = openAIClient
        self.idProvider = idProvider
    }

    // MARK: - Events
    func createConversation(type: ConversationType = .normal, assistantId: String? = nil) {
        let conversation = Conversation(id: idProvider(), messages: [], type: type, assistantId: assistantId)
        conversations.append(conversation)
    }

    func selectConversation(_ conversationId: Conversation.ID?) {
        selectedConversationID = conversationId
    }

    func deleteConversation(_ conversationId: Conversation.ID) {
        conversations.removeAll(where: { $0.id == conversationId })
    }

    @MainActor
    func sendMessage(
        _ message: Message,
        conversationId: Conversation.ID,
        model: Model
    ) async {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }) else {
            return
        }

        switch conversations[conversationIndex].type  {
        case .normal:
            conversations[conversationIndex].messages.append(message)

            await completeChat(
                conversationId: conversationId,
                model: model
            )
            // For assistant case we send chats to thread and then poll, polling will receive sent chat + new assistant messages.
        case .assistant:

            // First message in an assistant thread.
            if conversations[conversationIndex].messages.count == 0 {

                var localMessage = message
                localMessage.isLocal = true
                conversations[conversationIndex].messages.append(localMessage)

                do {
                    let threadsQuery = ThreadsQuery(messages: [Chat(role: message.role, content: message.content)])
                    let threadsResult = try await openAIClient.threads(query: threadsQuery)

                    guard let currentAssistantId = conversations[conversationIndex].assistantId else { return print("No assistant selected.")}

                    let runsQuery = RunsQuery(assistantId:  currentAssistantId)
                    let runsResult = try await openAIClient.runs(threadId: threadsResult.id, query: runsQuery)

                    // check in on the run every time the poller gets hit.
                    startPolling(conversationId: conversationId, runId: runsResult.id, threadId: threadsResult.id)
                }
                catch {
                    print("error: \(error) creating thread w/ message")
                }
            }
            // Subsequent messages on the assistant thread.
            else {

                var localMessage = message
                localMessage.isLocal = true
                conversations[conversationIndex].messages.append(localMessage)

                do {
                    guard let currentThreadId else { return print("No thread to add message to.")}

                    let _ = try await openAIClient.threadsAddMessage(threadId: currentThreadId,
                                                                     query: ThreadAddMessageQuery(role: message.role.rawValue, content: message.content))

                    guard let currentAssistantId = conversations[conversationIndex].assistantId else { return print("No assistant selected.")}

                    let runsQuery = RunsQuery(assistantId: currentAssistantId)
                    let runsResult = try await openAIClient.runs(threadId: currentThreadId, query: runsQuery)

                    // check in on the run every time the poller gets hit.
                    startPolling(conversationId: conversationId, runId: runsResult.id, threadId: currentThreadId)
                }
                catch {
                    print("error: \(error) adding to thread w/ message")
                }
            }
        }
    }

    @MainActor
    func completeChat(
        conversationId: Conversation.ID,
        model: Model
    ) async {
        guard let conversation = conversations.first(where: { $0.id == conversationId }) else {
            return
        }

        conversationErrors[conversationId] = nil

        do {
            guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }) else {
                return
            }

            let weatherFunction = ChatFunctionDeclaration(
                name: "getWeatherData",
                description: "Get the current weather in a given location",
                parameters: .init(
                    type: .object,
                    properties: [
                        "location": .init(type: .string, description: "The city and state, e.g. San Francisco, CA")
                    ],
                    required: ["location"]
                )
            )

            let functions = [weatherFunction]

            let chatsStream: AsyncThrowingStream<ChatStreamResult, Error> = openAIClient.chatsStream(
                query: ChatQuery(
                    model: model,
                    messages: conversation.messages.map { message in
                        Chat(role: message.role, content: message.content)
                    },
                    functions: functions
                )
            )

            var functionCallName = ""
            var functionCallArguments = ""
            for try await partialChatResult in chatsStream {
                for choice in partialChatResult.choices {
                    let existingMessages = conversations[conversationIndex].messages
                    // Function calls are also streamed, so we need to accumulate.
                    if let functionCallDelta = choice.delta.functionCall {
                        if let nameDelta = functionCallDelta.name {
                            functionCallName += nameDelta
                        }
                        if let argumentsDelta = functionCallDelta.arguments {
                            functionCallArguments += argumentsDelta
                        }
                    }
                    var messageText = choice.delta.content ?? ""
                    if let finishReason = choice.finishReason,
                       finishReason == "function_call" {
                        messageText += "Function call: name=\(functionCallName) arguments=\(functionCallArguments)"
                    }
                    let message = Message(
                        id: partialChatResult.id,
                        role: choice.delta.role ?? .assistant,
                        content: messageText,
                        createdAt: Date(timeIntervalSince1970: TimeInterval(partialChatResult.created))
                    )
                    if let existingMessageIndex = existingMessages.firstIndex(where: { $0.id == partialChatResult.id }) {
                        // Meld into previous message
                        let previousMessage = existingMessages[existingMessageIndex]
                        let combinedMessage = Message(
                            id: message.id, // id stays the same for different deltas
                            role: message.role,
                            content: previousMessage.content + message.content,
                            createdAt: message.createdAt
                        )
                        conversations[conversationIndex].messages[existingMessageIndex] = combinedMessage
                    } else {
                        conversations[conversationIndex].messages.append(message)
                    }
                }
            }
        } catch {
            conversationErrors[conversationId] = error
        }
    }

    // Start Polling section
    func startPolling(conversationId: Conversation.ID, runId: String, threadId: String) {
        currentRunId = runId
        currentThreadId = threadId
        currentConversationId = conversationId
        isSendingMessage = true
        timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.timerFired()
            }
        }
    }

    func stopPolling() {
        isSendingMessage = false
        timer?.invalidate()
        timer = nil
    }

    private func timerFired() {
        Task {
            let result = try await openAIClient.runRetrieve(threadId: currentThreadId ?? "", runId: currentRunId ?? "")

            // TESTING RETRIEVAL OF RUN STEPS
            handleRunRetrieveSteps()

            switch result.status {
                // Get threadsMesages.
            case "completed":
                handleCompleted()
                break
            case "failed":
                // Handle more gracefully with a popup dialog or failure indicator
                await MainActor.run {
                    self.stopPolling()
                }
                break
            default:
                // Handle additional statuses "requires_action", "queued" ?, "expired", "cancelled"
                // https://platform.openai.com/docs/assistants/how-it-works/runs-and-run-steps
                break
            }
        }
    }
    // END Polling section
    
    // This function is called when a thread is marked "completed" by the run status API.
    private func handleCompleted() {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == currentConversationId }) else {
            return
        }
        Task {
            await MainActor.run {
                self.stopPolling()
            }
            // Once a thread is marked "completed" by the status API, we can retrieve the threads messages, including a pagins cursor representing the last message we received.
            var before: String?
            if let lastNonLocalMessage = self.conversations[conversationIndex].messages.last(where: { $0.isLocal == false }) {
                before = lastNonLocalMessage.id
            }

            let result = try await openAIClient.threadsMessages(threadId: currentThreadId ?? "", before: before)

            for item in result.data.reversed() {
                let role = item.role
                for innerItem in item.content {
                    let message = Message(
                        id: item.id,
                        role: Chat.Role(rawValue: role) ?? .user,
                        content: innerItem.text?.value ?? "",
                        createdAt: Date(),
                        isLocal: false // Messages from the server are not local
                    )
                    await MainActor.run {
                        // Check if this message from the API matches a local message
                        if let localMessageIndex = self.conversations[conversationIndex].messages.firstIndex(where: { $0.isLocal == true }) {

                            // Replace the local message with the API message
                            self.conversations[conversationIndex].messages[localMessageIndex] = message
                        } else {
                            // This is a new message from the server, append it
                            self.conversations[conversationIndex].messages.append(message)
                        }
                    }
                }
            }
        }
    }
    
    // The run retrieval steps are fetched in a separate task. This request is fetched, checking for new run steps, each time the run is fetched.
    private func handleRunRetrieveSteps() {
        Task {
            guard let conversationIndex = conversations.firstIndex(where: { $0.id == currentConversationId }) else {
                return
            }
            var before: String?
//            if let lastRunStepMessage = self.conversations[conversationIndex].messages.last(where: { $0.isRunStep == true }) {
//                before = lastRunStepMessage.id
//            }

            let stepsResult = try await openAIClient.runRetrieveSteps(threadId: currentThreadId ?? "", runId: currentRunId ?? "", before: before)

            for item in stepsResult.data.reversed() {
                let toolCalls = item.stepDetails.toolCalls?.reversed() ?? []

                for step in toolCalls {
                    // TODO: Depending on the type of tool tha is used we can add additional information here
                    // ie: if its a retrieval: add file information, code_interpreter: add inputs and outputs info, or function: add arguemts and additional info.
                    let msgContent: String
                    switch step.type {
                    case "retrieval":
                        msgContent = "RUN STEP: \(step.type)"

                    case "code_interpreter":
                        msgContent = "code_interpreter\ninput:\n\(step.code?.input ?? "")\noutputs: \(step.code?.outputs?.first?.logs ?? "")"

                    default:
                        msgContent = "RUN STEP: \(step.type)"

                    }
                    let runStepMessage = Message(
                        id: step.id,
                        role: .assistant,
                        content: msgContent,
                        createdAt: Date(),
                        isRunStep: true
                    )
                    await MainActor.run {
                        if let localMessageIndex = self.conversations[conversationIndex].messages.firstIndex(where: { $0.isRunStep == true && $0.id == step.id }) {
                            self.conversations[conversationIndex].messages[localMessageIndex] = runStepMessage
                        }
                        else {
                            self.conversations[conversationIndex].messages.append(runStepMessage)
                        }
                    }
                }
            }
        }
    }
}
