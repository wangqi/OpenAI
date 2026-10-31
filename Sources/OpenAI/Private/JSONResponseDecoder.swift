//
//  File.swift
//  OpenAI
//
//  Created by Oleksii Nezhyborets on 09.06.2025.
//

import Foundation

struct JSONResponseDecoder {
    let parsingOptions: ParsingOptions
    
    func decodeResponseData<ResultType: Codable>(_ data: Data) throws -> ResultType {
        let responseDecoder = JSONDecoder()
        responseDecoder.userInfo[.parsingOptions] = parsingOptions
        
        do {
            return try responseDecoder.decode(ResultType.self, from: data)
        } catch {
            let errorDecoder = JSONResponseErrorDecoder(decoder: JSONDecoder())
            
            if let decodedError = errorDecoder.decodeErrorResponse(data: data) {
                throw decodedError
            }
            // A flat {"code": "...", "error": "..."} error body (xAI) matched neither shape above, so a
            // failed non-streaming request surfaced as a DecodingError on the success type and the
            // provider's message was lost. The streaming path already reports this shape as
            // APICommonError. // wangqi modified 2026-10-31
            if let commonError = try? JSONDecoder().decode(APICommonError.self, from: data) {
                throw commonError
            }
            throw error
        }
    }
}
