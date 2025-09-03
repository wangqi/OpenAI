//
//  ServerSentEventsStreamInterpreter.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 11.03.2025.
//

import Foundation

/// https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
/// 9.2.6 Interpreting an event stream
///
/// - Note: This class is NOT thread safe. It is a caller's responsibility to call all the methods in a thread-safe manner.
final class ServerSentEventsStreamInterpreter <ResultType: Codable & Sendable>: @unchecked Sendable, StreamInterpreter {
    private let parser = ServerSentEventsStreamParser()
    private let streamingCompletionMarker = "[DONE]"
    private var previousChunkBuffer = ""
    
    private var onEventDispatched: ((ResultType) -> Void)?
    private var onError: ((Error) -> Void)?
    private let parsingOptions: ParsingOptions
    
    enum InterpeterError: Error {
        case unhandledStreamEventType(String)
    }
    
    init(parsingOptions: ParsingOptions) {
        self.parsingOptions = parsingOptions
        
        parser.setCallbackClosures { [weak self] event in
            self?.processEvent(event)
        } onError: { [weak self] error in
            self?.onError?(error)
        }
    }
    
    /// Sets closures an instance of type. Not thread safe.
    ///
    /// - Parameters:
    ///     - onEventDispatched: Can be called multiple times per `processData`
    ///     - onError: Will only be called once per `processData`
    func setCallbackClosures(onEventDispatched: @escaping @Sendable (ResultType) -> Void, onError: @escaping @Sendable (Error) -> Void) {
        self.onEventDispatched = onEventDispatched
        self.onError = onError
    }
    
    /// Not thread safe
    func processData(_ data: Data) {
        let decoder = JSONDecoder()
        if let decoded = JSONResponseErrorDecoder(decoder: decoder).decodeErrorResponse(data: data) {
            onError?(decoded)
            return
        }
        
        parser.processData(data: data)
    }
    
    /*
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
    }
     */
    
    private func processEvent(_ event: ServerSentEventsStreamParser.Event) {
        switch event.eventType {
        case "message":
            let jsonContent = event.decodedData
            guard jsonContent != streamingCompletionMarker && !jsonContent.isEmpty else {
                return
            }
            guard let jsonData = jsonContent.data(using: .utf8) else {
                onError?(StreamingError.unknownContent)
                return
            }
            
            let decoder = JSONResponseDecoder(parsingOptions: parsingOptions)
            do {
                let object: ResultType = try decoder.decodeResponseData(jsonData)
                onEventDispatched?(object)
            } catch DecodingError.dataCorrupted(_) {
                // Ignore this specific error
                let jsonString = String(data: jsonData, encoding: .utf8)
                print("Warning: dataCorrupted, json: \(jsonString)")
                print("It may be due to incomplete JSON data in the stream. Waiting for the next chunk...")
            } catch {
                if let errorString = String(data: jsonData, encoding: .utf8) {
                    // Try to extract useful error information from partial JSON
                    // wangqi 2025-09-02
                    if let extractedError = extractErrorFromPartialJSON(errorString) {
                        onError?(extractedError)
                        return
                    }
                    print("Partial JSON content error: \(errorString). Ignore it")
                    return
                } else {
                    onError?(error)
                }
            }
        case "error":
            //wangqi modified 2025-08-27
            let jsonContent = event.decodedData
            var errorMessage = jsonContent
            
            // Try to parse as JSON and extract the error message
            if let jsonData = jsonContent.data(using: .utf8) {
                do {
                    let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                    
                    // Try standard OpenAI error format: {"error": {"message": "..."}}
                    if let errorObj = jsonObject?["error"] as? [String: Any],
                       let message = errorObj["message"] as? String {
                        errorMessage = message
                    }
                    // Try direct message format: {"message": "..."}
                    else if let message = jsonObject?["message"] as? String {
                        errorMessage = message
                    }
                    // Try error field directly as string: {"error": "message"}
                    else if let message = jsonObject?["error"] as? String {
                        errorMessage = message
                    }
                } catch {
                    // JSON parsing failed, use raw content
                }
            }
            
            // Clean up the error message and create error object
            let cleanedMessage = cleanErrorMessage(errorMessage.isEmpty ? "Unknown streaming error occurred" : errorMessage)
            let formattedError = APICommonError(code: "Remote server message", error: cleanedMessage)
            onError?(formattedError)
        default:
            // Handle truly unknown event types
            let unknownError = APICommonError(code: "UNKNOWN_EVENT", error: "Unknown event type: \(event.eventType)")
            onError?(unknownError)
        }
    }
    
    // Clean up technical error messages to make them user-friendly using pattern recognition
    private func cleanErrorMessage(_ message: String) -> String {
        var cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pattern 1: Remove "Error in <verb>ing <noun> stream: " pattern
        let streamErrorPattern = #"^Error in \w+ing \w+ stream: "#
        cleaned = cleaned.replacingOccurrences(of: streamErrorPattern, with: "", options: .regularExpression)
        
        // Pattern 2: Remove Python exception types (XxxxError: or XxxxException:)
        let pythonExceptionPattern = #"^[A-Z][a-zA-Z]*(?:Error|Exception): "#
        cleaned = cleaned.replacingOccurrences(of: pythonExceptionPattern, with: "", options: .regularExpression)
        
        // Pattern 3: Remove generic "Error: " prefix
        let genericErrorPattern = #"^Error: "#
        cleaned = cleaned.replacingOccurrences(of: genericErrorPattern, with: "", options: .regularExpression)
        
        // Trim whitespace again after pattern removal
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Capitalize first letter if needed
        if !cleaned.isEmpty {
            cleaned = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        
        return cleaned.isEmpty ? "An error occurred while processing your request" : cleaned
    }
    
    // Extract error information from partial JSON strings using simple string operations
    // wangqi 2025-09-02
    private func extractErrorFromPartialJSON(_ partialJSON: String) -> APICommonError? {
        let code = extractCode(from: partialJSON)
        let message = extractMessage(from: partialJSON)
        
        if let message = message {
            return APICommonError(code: code ?? "", error: message)
        } else if let code = code {
            return APICommonError(code: code, error: partialJSON)
        }
        
        return nil
    }
    
    // Extract the first "code" field value
    private func extractCode(from json: String) -> String? {
        guard let codeRange = json.range(of: "\"code\":") else { return nil }
        
        let afterColon = codeRange.upperBound
        
        // Skip whitespace
        var index = afterColon
        while index < json.endIndex && json[index].isWhitespace {
            index = json.index(after: index)
        }
        
        // Extract number - fix bounds checking to prevent crash
        var numberEnd = index
        while numberEnd < json.endIndex && json[numberEnd].isWholeNumber {
            numberEnd = json.index(after: numberEnd)
        }
        
        if index < numberEnd {
            return String(json[index..<numberEnd])
        }
        
        return nil
    }
    
    // Extract the deepest message by finding all messages and picking the shortest one (likely innermost)
    // This function handles complex nested JSON with escaped quotes to find the most relevant error message
    private func extractMessage(from json: String) -> String? {
        var messages: [String] = []
        var searchString = json
        
        // Search for all "message": fields in the JSON string
        while true {
            let messageRange = findNextMessageField(in: searchString)
            guard let range = messageRange else { break }
            
            // Move past "message": or \"message\":
            searchString = String(searchString[range.upperBound...])
            
            // Skip whitespace after the colon
            while searchString.hasPrefix(" ") || searchString.hasPrefix("\t") {
                searchString = String(searchString.dropFirst())
            }
            
            // Extract the message value based on quote type
            if let (message, remainingString) = extractQuotedValue(from: searchString) {
                // Skip ConnectionError wrapper messages to get to the real error
                if !message.starts(with: "ConnectionError:") {
                    let unescapedMessage = unescapeJSONString(message)
                    messages.append(unescapedMessage)
                }
                searchString = remainingString
            }
        }
        
        // Return the shortest message (most specific/innermost error)
        return messages.filter { !$0.isEmpty }.min(by: { $0.count < $1.count })
    }
    
    // Find the next "message": field, handling both regular and escaped quotes
    private func findNextMessageField(in string: String) -> Range<String.Index>? {
        let patterns = ["\"message\":", "\\\"message\\\":"]
        var earliestRange: Range<String.Index>? = nil
        
        for pattern in patterns {
            if let range = string.range(of: pattern) {
                if let existing = earliestRange {
                    if range.lowerBound < existing.lowerBound {
                        earliestRange = range
                    }
                } else {
                    earliestRange = range
                }
            }
        }
        
        return earliestRange
    }
    
    // Extract a quoted string value, handling both regular and escaped quotes
    // Returns: (extracted_value, remaining_string) or nil if no valid quoted string found
    private func extractQuotedValue(from string: String) -> (String, String)? {
        var searchString = string
        
        // Determine quote type and skip opening quote
        let (quoteType, contentStart) = getQuoteTypeAndStart(from: searchString)
        guard let quotePattern = quoteType, let startIndex = contentStart else { return nil }
        
        searchString = String(searchString[startIndex...])
        
        // Find the matching closing quote
        if let endIndex = findClosingQuote(in: searchString, for: quotePattern) {
            let extractedValue = String(searchString[..<endIndex])
            let remainingString = String(searchString[endIndex...])
            return (extractedValue, remainingString)
        }
        
        return nil
    }
    
    // Identify quote type and return the start position of actual content
    private func getQuoteTypeAndStart(from string: String) -> (String?, String.Index?) {
        if string.hasPrefix("\\\"") {
            // Escaped quote: \"
            let startIndex = string.index(string.startIndex, offsetBy: 2)
            return ("\\\"", startIndex)
        } else if string.hasPrefix("\"") {
            // Regular quote: "
            let startIndex = string.index(after: string.startIndex)
            return ("\"", startIndex)
        }
        return (nil, nil)
    }
    
    // Find the matching closing quote, handling escape sequences
    private func findClosingQuote(in string: String, for quoteType: String) -> String.Index? {
        var index = string.startIndex
        
        while index < string.endIndex {
            if quoteType == "\\\"" {
                // Looking for closing \" (but not \\\")
                if index < string.index(before: string.endIndex) {
                    let nextIndex = string.index(after: index)
                    if string[index] == "\\" && string[nextIndex] == "\"" {
                        // Check if this backslash is itself escaped (\\")
                        let isEscapedBackslash = index > string.startIndex && 
                                               string[string.index(before: index)] == "\\"
                        if !isEscapedBackslash {
                            return index // Found unescaped \"
                        }
                        // Skip the escaped sequence
                        index = string.index(after: nextIndex)
                        continue
                    }
                }
            } else {
                // Looking for closing " (but not \")
                if string[index] == "\"" {
                    let isEscaped = index > string.startIndex && 
                                   string[string.index(before: index)] == "\\"
                    if !isEscaped {
                        return index // Found unescaped "
                    }
                }
            }
            index = string.index(after: index)
        }
        
        return nil
    }
    
    // Unescape standard JSON string escape sequences
    private func unescapeJSONString(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\\\\"", with: "\"")  // \\\" -> "
            .replacingOccurrences(of: "\\\"", with: "\"")     // \" -> "
            .replacingOccurrences(of: "\\n", with: "\n")      // \n -> newline
            .replacingOccurrences(of: "\\r", with: "\r")      // \r -> carriage return  
            .replacingOccurrences(of: "\\t", with: "\t")      // \t -> tab
            .replacingOccurrences(of: "\\\\", with: "\\")     // \\ -> \
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
