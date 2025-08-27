//
//  APIError.swift
//  
//
//  Created by Sergii Kryvoblotskyi on 02/04/2023.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenAIError: DescribedError {
    case emptyData
    case statusError(response: HTTPURLResponse, statusCode: Int)
}

public struct APIError: Error, Decodable, Equatable {
    public let message: String
    public let type: String
    public let param: String?
    public let code: String?
  
  public init(message: String, type: String, param: String?, code: String?) {
    self.message = message
    self.type = type
    self.param = param
    self.code = code
  }
  
  enum CodingKeys: CodingKey {
    case message
    case type
    case param
    case code
  }
  
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    
    //
    // message can be String or [String].
    //
    if let string = try? container.decode(String.self, forKey: .message) {
      self.message = string
    } else if let array = try? container.decode([String].self, forKey: .message) {
      self.message = array.joined(separator: "\n")
    } else {
      throw DecodingError.typeMismatch(String.self, .init(codingPath: [CodingKeys.message], debugDescription: "message: expected String or [String]"))
    }
    
    self.type = try container.decode(String.self, forKey: .type)
    self.param = try container.decodeIfPresent(String.self, forKey: .param)
    self.code = try container.decodeIfPresent(String.self, forKey: .code)
  }
}

extension APIError: LocalizedError {
    
    public var errorDescription: String? {
        return message
    }
}

public struct APIErrorResponse: ErrorResponse {
    public let error: APIError
    
    public var errorDescription: String? {
        error.errorDescription
    }
}

// wangqi defined api error
public struct APICommonError: Error, Decodable, Equatable, CustomStringConvertible {
    let code: String
    let error: String
    
    enum CodingKeys: CodingKey {
        case code
        case error
    }
    
    public init(code: String, error: String) {
        self.error = error
        self.code = code
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.error = try container.decode(String.self, forKey: .error)
        self.code = try container.decode(String.self, forKey: .code)
    }
    
    // wangqi modified 2025-08-27
    // Provides a user-friendly error message like system errors
    public var localizedDescription: String {
        return "\(error)"
    }
    
    // Allows String(error) to return localizedDescription
    public var description: String {
        return localizedDescription
    }
}

public protocol ErrorResponse: Error, Decodable, Equatable, LocalizedError {
    associatedtype Err: Error, Decodable, Equatable, LocalizedError
    
    var error: Err { get }
    var errorDescription: String? { get }
}
