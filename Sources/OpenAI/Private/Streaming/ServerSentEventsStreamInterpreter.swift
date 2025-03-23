//
//  ServerSentEventsStreamInterpreter.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 11.03.2025.
//

import Foundation

/// https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
/// 9.2.6 Interpreting an event stream
final class ServerSentEventsStreamInterpreter <ResultType: Codable & Sendable>: @unchecked Sendable, StreamInterpreter {
    private let streamingCompletionMarker = "[DONE]"
    private var previousChunkBuffer = ""
    
    private var onEventDispatched: ((ResultType) -> Void)?
    private var onError: ((Error) -> Void)?
    private let executionSerializer: ExecutionSerializer
    
    init(executionSerializer: ExecutionSerializer = GCDQueueAsyncExecutionSerializer(queue: .userInitiated)) {
        self.executionSerializer = executionSerializer
    }
    
    /// Sets closures an instance of type in a thread safe manner
    ///
    /// - Parameters:
    ///     - onEventDispatched: Can be called multiple times per `processData`
    ///     - onError: Will only be called once per `processData`
    func setCallbackClosures(onEventDispatched: @escaping @Sendable (ResultType) -> Void, onError: @escaping @Sendable (Error) -> Void) {
        executionSerializer.dispatch {
            self.onEventDispatched = onEventDispatched
            self.onError = onError
        }
    }
    
    func processData(_ data: Data) {
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(APIErrorResponse.self, from: data) {
            onError?(decoded)
            return
        }
        
        guard let stringContent = String(data: data, encoding: .utf8) else {
            onError?(StreamingError.unknownContent)
            return
        }
        
        //When errors happens, the main urlSession will complete before error .onError() is called.
        //Disable multiple thread here.
        //wangqi 2023-03-25
        
        //executionSerializer.dispatch {
        //    self.processJSON(from: stringContent)
        //}
        self.processJSON(from: stringContent)
    }
    
    private func processJSON(from stringContent: String) {
        if stringContent.isEmpty {
            return
        }

        let fullChunk = "\(previousChunkBuffer)\(stringContent)"
        let chunkLines = fullChunk
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        
        //wangqi added 2025-03-23
        var fullJsonString: String = ""

        var jsonObjects: [String] = []
        for line in chunkLines {

            // Skip comments
            if line.starts(with: ":") { continue }

            // Get JSON object
            let jsonData = line
                .components(separatedBy: "data:")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            
            //jsonObjects.append(contentsOf: jsonData)
            // Check if jsonData is a valid JSON
            // wangqi 2025-03-23
            if decodeFirstMatching(jsonString: jsonData.joined(), as: [ResultType.self, APIErrorResponse.self]) != nil {
                jsonObjects.append(contentsOf: jsonData)
            } else {
                fullJsonString += jsonData.joined()
            }
        }
        //In case responses are not valid json
        if jsonObjects.isEmpty {
            jsonObjects.append(fullJsonString)
        }

        previousChunkBuffer = ""
        
        guard jsonObjects.isEmpty == false, jsonObjects.first != streamingCompletionMarker else {
            return
        }
        
        jsonObjects.enumerated().forEach { (index, jsonContent)  in
            guard jsonContent != streamingCompletionMarker && !jsonContent.isEmpty else {
                return
            }
            guard let jsonData = jsonContent.data(using: .utf8) else {
                onError?(StreamingError.unknownContent)
                return
            }
            let decoder = JSONDecoder()
            do {
                let object = try decoder.decode(ResultType.self, from: jsonData)
                onEventDispatched?(object)
            } catch {
                if let decoded = try? decoder.decode(APIErrorResponse.self, from: jsonData) {
                    onError?(decoded)
                    return
                } else if let errorString = String(data: jsonData, encoding: .utf8) {
                    // Fallback: construct new error response from plain string
                    // wangqi 2025-03-23
                    let fallbackError = APICommonError(code: "11", error: fullJsonString)
                    onError?(fallbackError)
                    return
                } else if index == jsonObjects.count - 1 {
                    previousChunkBuffer = "data: \(jsonContent)" // Chunk ends in a partial JSON
                } else {
                    onError?(error)
                }
            }
        }
    }
    
    // Test if the mulitple Decodable can be used to parse the jsonString
    // wangqi 2025-03-23
    func decodeFirstMatching(jsonString: String, as types: [Decodable.Type]) -> Decodable? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        for type in types {
            if let decoded = try? decoder.decode(type, from: data) {
                return decoded
            }
        }
        return nil
    }
}
