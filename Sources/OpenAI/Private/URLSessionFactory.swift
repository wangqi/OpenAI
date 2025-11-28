//
//  URLSessionFactory.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 10.03.2025.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol URLSessionFactory: Sendable {
    func makeUrlSession(delegate: URLSessionDataDelegateProtocol) -> URLSessionProtocol
}

struct FoundationURLSessionFactory: URLSessionFactory {
    func makeUrlSession(delegate: URLSessionDataDelegateProtocol) -> any URLSessionProtocol {
        let forwarder = URLSessionDataDelegateForwarder(target: delegate)
        return URLSession(configuration: .default, delegate: forwarder, delegateQueue: nil)
    }
}

// wangqi 2025-11-28: Add configurable URLSession factory for proxy support
/// A URLSessionFactory that uses a custom URLSessionConfiguration
/// This allows proxy settings to be applied to streaming requests
public struct ConfigurableURLSessionFactory: URLSessionFactory, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration) {
        self.configuration = configuration
    }

    func makeUrlSession(delegate: URLSessionDataDelegateProtocol) -> any URLSessionProtocol {
        let forwarder = URLSessionDataDelegateForwarder(target: delegate)
        return URLSession(configuration: configuration, delegate: forwarder, delegateQueue: nil)
    }
}
