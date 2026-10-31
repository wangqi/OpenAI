//
//  JSONResponseDecoderFlatErrorTests.swift
//  OpenAI
//
//  A flat {"code","error"} error body (xAI) must surface as APICommonError, not as a
//  DecodingError on the success type. // wangqi modified 2026-10-31
//

import XCTest
@testable import OpenAI

final class JSONResponseDecoderFlatErrorTests: XCTestCase {

    private let decoder = JSONResponseDecoder(parsingOptions: [])

    func testFlatErrorBodyThrowsAPICommonError() {
        let body = #"{"code":"400","error":"Argument not supported: instructions and previous_response_id together"}"#
        XCTAssertThrowsError(try decoder.decodeResponseData(Data(body.utf8)) as ModelsResult) { error in
            guard let common = error as? APICommonError else {
                return XCTFail("expected APICommonError, got \(error)")
            }
            XCTAssertEqual(common.code, "400")
            XCTAssertEqual(common.error, "Argument not supported: instructions and previous_response_id together")
        }
    }

    func testOpenAIErrorBodyStillThrowsAPIErrorResponse() {
        let body = #"{"error":{"message":"Invalid model id","type":"invalid_request_error","param":null,"code":null}}"#
        XCTAssertThrowsError(try decoder.decodeResponseData(Data(body.utf8)) as ModelsResult) { error in
            XCTAssertTrue(error is APIErrorResponse, "got \(error)")
        }
    }

    func testUnrelatedBodyStillThrowsDecodingError() {
        XCTAssertThrowsError(try decoder.decodeResponseData(Data(#"{"foo":1}"#.utf8)) as ModelsResult) { error in
            XCTAssertTrue(error is DecodingError, "got \(error)")
        }
    }
}
