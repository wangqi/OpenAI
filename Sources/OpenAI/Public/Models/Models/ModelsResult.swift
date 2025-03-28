//
//  ModelsResult.swift
//
//
//  Created by Aled Samuel on 08/04/2023.
//

import Foundation

/// A list of model objects.
public struct ModelsResult: Codable, Equatable, Sendable {

    /// A list of model objects.
    public let data: [ModelResult]
    /// The object type, which is always `list`
    public let object: String
    
    // MARK: - wangqi 2025-03-28
    
    public enum CodingKeys: String, CodingKey {
        case data
        case object
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode `data` (required)
        data = try container.decode([ModelResult].self, forKey: .data)

        // Decode `object`, fallback to "list" if missing
        object = try container.decodeIfPresent(String.self, forKey: .object) ?? "list"
    }

    // Optional: for symmetry, you may want to provide a custom encoder
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encode(object, forKey: .object)
    }
}
