//
//  StreamInterpreter.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 03.02.2025.
//

import Foundation

protocol StreamInterpreter: AnyObject {
    associatedtype ResultType: Codable
    
    var onEventDispatched: ((ResultType) -> Void)? { get set }
    
    func processData(_ data: Data) throws
}

/// https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
/// 9.2.6 Interpreting an event stream
class ServerSentEventsStreamInterpreter<ResultType: Codable>: StreamInterpreter {
    private let streamingCompletionMarker = "[DONE]"
    private var previousChunkBuffer = ""
    
    var onEventDispatched: ((ResultType) -> Void)?
    
    func processData(_ data: Data) throws {
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(APIErrorResponse.self, from: data) {
            throw decoded
        }
        
        guard let stringContent = String(data: data, encoding: .utf8) else {
            throw StreamingError.unknownContent
        }
        try processJSON(from: stringContent)
    }
    
    private func processJSON(from stringContent: String) throws {
        if stringContent.isEmpty {
            return
        }

        let fullChunk = "\(previousChunkBuffer)\(stringContent)"
        let chunkLines = fullChunk
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        var jsonObjects: [String] = []
        var fullJsonString: String = ""
        for line in chunkLines {

            // Skip comments
            if line.starts(with: ":") { continue }

            // Get JSON object
            let jsonData = line
                .components(separatedBy: "data:")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            // Check if jsonData is a valid JSON
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
        
        try jsonObjects.enumerated().forEach { (index, jsonContent)  in
            guard jsonContent != streamingCompletionMarker && !jsonContent.isEmpty else {
                return
            }
            guard let jsonData = jsonContent.data(using: .utf8) else {
                throw StreamingError.unknownContent
            }
            let decoder = JSONDecoder()
            do {
                let object = try decoder.decode(ResultType.self, from: jsonData)
                onEventDispatched?(object)
            } catch {
                // Try to decode as APIErrorResponse
                if let decoded = try? decoder.decode(APIErrorResponse.self, from: jsonData) {
                    throw decoded
                } else if let errorString = String(data: jsonData, encoding: .utf8) {
                    // Fallback: construct new error response from plain string
                    let fallbackError = APICommonError(code: "11", error: errorString)
                    throw fallbackError
                } else if index == jsonObjects.count - 1 {
                    previousChunkBuffer = "data: \(jsonContent)" // chunk ends in a partial JSON
                } else {
                    throw error
                }
            }
        }
    }
    
    // Test if the mulitple Decodable can be used to parse the jsonString
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
