//
//  Model.swift
//
//
//  Created by Aled Samuel on 08/04/2023.
//

import Foundation

/// The model object matching the specified ID.
public struct ModelResult: Codable, Equatable, Sendable {

    /// The model identifier, which can be referenced in the API endpoints.
    public let id: String
    /// The Unix timestamp (in seconds) when the model was created.
    public let created: TimeInterval
    /// The object type, which is always "model".
    public let object: String
    /// The organization that owns the model.
    public let ownedBy: String

    public enum CodingKeys: String, CodingKey {
        case id
        case created
        case object
        case ownedBy = "owned_by"
    }
    
    // Custom decoder to provide a default value for `created`
    // wangqi 2025-03-23
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        created = try container.decodeIfPresent(TimeInterval.self, forKey: .created) ?? 0  // Default to `0`
        object = try container.decode(String.self, forKey: .object)
        ownedBy = try container.decode(String.self, forKey: .ownedBy)
    }
}
