//
//  ServiceTier.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 22.05.2025.
//

import Foundation

public enum ServiceTier: String, Codable, Hashable, Sendable, CaseIterable {
    case auto = "auto"
    case defaultTier = "default"
    case flexTier = "flex"
    case onDemand = "on_demand"
}

// wangqi 2026-01-08: Added typealias to disambiguate from potential conflicts
public typealias ResponsesAPIServiceTier = ServiceTier
