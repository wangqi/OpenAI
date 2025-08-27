//
//  MediaContentFactory.swift
//
//  Created by wangqi on 2025-08-27.
//

import Foundation

// MARK: - Media Content

/*
 {
     "id": "gen-1756265213-g3hPBoRCCp6t5J0dMYsq",
     "provider": "Google AI Studio",
     "model": "google/gemini-2.5-flash-image-preview: free",
     "object": "chat.comple-tion. chunk",
     "created": 1756265213,
     "choices":
     {
         "index": 0,
         "delta":
         {
             "role": "assistant",
             "content": "",
             "images":
             [
                 {
                     "type": "image_url",
                     "image_url":
                     {
                         "url": "data: image/png; base64, iVBORweKGgoAAAANSUhEUgAABAAAAAQA-CAIAAADwf7ZUAAAgAE1EQVR4nGz9W9tmN44jCgJc-YTttZ1aeqmvfzd38/ z82s3d3dWdm2RGvMBcAqBX1jPPgi097D1oSCYIgJfEv/ 6//9+CA1DkQSIAkCOIcEQKpIz5DQABAApIkYWYkgQIo-CICUORAAitIBh37bEEc1ВwQ+H5Ci4N8fCB1ApEDg-AP7EISjgHA14RiCPRIAiQRJnCEk4AAj69eiAQAIANBx-A01J+Ag51zpEG5FAi/ BGAB0pIngwAInA0QIKcvEQaUvsSAToaEENRkPyhw5nR+ SDPJnoweQ885SQlnC0QmTTBHwKK80NSgiTycKiT-B6FwdCTwGZyTmZGfE5AEAhDkX4FzPp8hSX70IYckd-DxgCRzP/ JHkefV0CMi0oL8AjjQZHqsncDigh55ZITkgyYMjaPCc-IwKgrQQkdSACBI8whDBDxeyOROgDPgOC0DkkwTkSJNp-KOfQ7qHNqDR5rbJccHh1BFOX5H3qqPEN2gRme-J0AP307hz6e8LgeTn+B4]1UCw0d59pgQJA6GPCd-f13k8EkGRM0divcsT6y+JT9gca4MAJWAw/ oIjEILAOCkJiqd0oYN5KN1EMKBs4Mg3fuRvwYzfq-PUikhBEHQniEHgA8ZxDYjjniDMDfCD6oYEhiD1Hp-D2RyHPZdz7TbweJQ+HkiT2hAgAdmx0JLhltcfkKef4g-HfHJpM+MjvwpXkARNisJsgkAIM/ niGIf8gAHwuHE3RD383iG0mdIG3ZREsAcHNY3M0CBM3/846/n4H/+5/+G8bONDCDznoP/..."
                     }
                 }
             ]
         }
     }
 }
 */

/// Represents media content (images, audio, video, etc.) from extended API responses
public struct MediaContent: Codable, Equatable, Sendable {
    /// The media type identifier from response JSON (e.g., "image_url", "audio_url")
    public let type: String
    
    /// MIME type extracted from data URL (e.g., "image/png", "audio/mp3")
    public let mimeType: String?
    
    /// Decoded binary data from base64 data URL
    public let data: Data
    
    /// Original data URL from response  
    public let url: String
    
    /// File size in bytes
    public var size: Int { data.count }
    
    public init(type: String, mimeType: String?, data: Data, url: String) {
        self.type = type
        self.mimeType = mimeType
        self.data = data
        self.url = url
    }
}

// MARK: - Media Content Factory

/// Factory for creating MediaContent from JSON decoder containers
class MediaContentFactory {
    
    /// Decode MediaContent from decoder container - the main entry point
    static func decodeMediaContent<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) -> [MediaContent]? {
        guard container.contains(key) else { return nil }
        
        // Decode as array of mixed-type dictionaries to handle nested structures like:
        // [{"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}}]
        if let images = try? container.decode([[String: SimpleJSON]].self, forKey: key) {
            let jsonArray = images.map { dict in
                dict.mapValues { $0.value }
            }
            return createMediaContent(from: jsonArray)
        }
        
        return nil
    }
    
    /// Create MediaContent from parsed JSON array
    private static func createMediaContent(from rawImages: [[String: Any]]) -> [MediaContent] {
        return rawImages.compactMap { item in
            guard let type = item["type"] as? String else { return nil }
            
            // Find data URL by recursively searching the JSON object
            guard let dataURL = findDataURL(in: item),
                  dataURL.hasPrefix("data:") else { return nil }
            
            // Extract MIME type: "data:image/png;base64,..." -> "image/png"
            let mimeType = extractMimeType(from: dataURL)
            
            // Decode base64 data: "data:image/png;base64,iVBORw0..." -> Data
            guard let data = extractBase64Data(from: dataURL) else { return nil }
            
            return MediaContent(
                type: type,
                mimeType: mimeType,
                data: data,
                url: dataURL
            )
        }
    }
    
    /// Extract MIME type from data URL
    private static func extractMimeType(from dataURL: String) -> String? {
        guard dataURL.hasPrefix("data:"),
              let semicolonRange = dataURL.range(of: ";") else { return nil }
        
        let mimeType = String(dataURL[dataURL.index(dataURL.startIndex, offsetBy: 5)..<semicolonRange.lowerBound])
        return mimeType.isEmpty ? nil : mimeType
    }
    
    /// Extract and decode base64 data from data URL
    private static func extractBase64Data(from dataURL: String) -> Data? {
        guard let commaRange = dataURL.range(of: ",") else { return nil }
        let base64String = String(dataURL[commaRange.upperBound...])
        return Data(base64Encoded: base64String)
    }
    
    /// Recursively search for data URL in JSON structure
    private static func findDataURL(in object: Any) -> String? {
        if let string = object as? String, string.hasPrefix("data:") {
            return string
        }
        
        if let dictionary = object as? [String: Any] {
            for value in dictionary.values {
                if let dataURL = findDataURL(in: value) {
                    return dataURL
                }
            }
        }
        
        if let array = object as? [Any] {
            for value in array {
                if let dataURL = findDataURL(in: value) {
                    return dataURL
                }
            }
        }
        
        return nil
    }
}

// MARK: - Simple JSON Helper

/// Lightweight helper for decoding mixed JSON values (strings, objects, arrays)
private struct SimpleJSON: Codable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let dict = try? container.decode([String: SimpleJSON].self) {
            value = dict.mapValues(\.value)
        } else if let array = try? container.decode([SimpleJSON].self) {
            value = array.map(\.value)
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        // Not needed for decoding-only use case
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}
