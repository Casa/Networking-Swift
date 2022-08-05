import Foundation
import XCTest

@testable
import Networking

final class LoggerTests: XCTestCase {
    var testInstance: NetworkingLogger!
    var sampleRequest: URLRequest!
    var sampleResponse: URLResponse!

    override func setUp() {
        testInstance = NetworkingLogger()

        sampleRequest = URLRequest(url: URL(string: "https://jsonplaceholder.typicode.com")!)
        sampleRequest.httpMethod = "GET"

        sampleResponse = URLResponse(url: URL(string: "https://jsonplaceholder.typicode.com")!, mimeType: "application/json", expectedContentLength: 42, textEncodingName: "utf8")
    }

    func testNoLogRequest() {
        let stringToLog = testInstance.requestLogString(request: sampleRequest)
        XCTAssertNil(stringToLog)        
    }

    func testNoLogResponse() {
        let stringToLog = testInstance.responseLogString(response: sampleResponse, data: Data())

        XCTAssertNil(stringToLog)
    }

    func testLogBasicRequest() {
        testInstance.logLevel = .info
        let stringToLog = testInstance.requestLogString(request: sampleRequest)

        XCTAssertNotNil(stringToLog)
        XCTAssert(stringToLog!.contains("GET to \'https://jsonplaceholder.typicode.com\'\n"))
        XCTAssert(stringToLog!.contains("HEADERS:\n"))
        XCTAssert(stringToLog!.contains("BODY:\n"))
    }

    func testLogBasiceResponse() {
        testInstance.logLevel = .info
        let stringToLog = testInstance.responseLogString(response: sampleResponse, data: Data())

        XCTAssertNotNil(stringToLog)
    }

    func testLogDebugRequest() {
        testInstance.logLevel = .debug
        let stringToLog = testInstance.requestLogString(request: sampleRequest)

        XCTAssert(stringToLog!.contains("curl")) 
    }

    func testLogRequestHeaders() {
        testInstance.logLevel = .info
        sampleRequest.addValue("doe", forHTTPHeaderField: "john")

        let stringToLog = testInstance.requestLogString(request: sampleRequest)
        XCTAssertNotNil(stringToLog)
        XCTAssertTrue(stringToLog!.contains("john : doe"))
    }

    func testLogRequestBody() {
        testInstance.logLevel = .info
        let jsonString = """
        {"title": "Hello world"}
        """
        sampleRequest.httpBody = jsonString.data(using: .utf8)

        let stringToLog = testInstance.requestLogString(request: sampleRequest)
        XCTAssertNotNil(stringToLog)
        XCTAssert(stringToLog!.contains("{\"title\": \"Hello world\"}"))
    }
}
