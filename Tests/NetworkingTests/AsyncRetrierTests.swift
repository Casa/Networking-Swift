//
//  AsyncRetrierTests.swift
//
//
//  Created by Logan Sease on 30/09/2026.
//

import Foundation
import XCTest

@testable
import Networking

/// Answers 401 to the first request and 200 to later ones, and records each request's
/// Authorization header.
private class UnauthorizedOnceURLProtocol: URLProtocol {

    static var authorizationHeaders = [String?]()

    override class func canInit(with request: URLRequest) -> Bool {
        return request.url?.host == "retrier.mocked.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        UnauthorizedOnceURLProtocol.authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
        let statusCode = UnauthorizedOnceURLProtocol.authorizationHeaders.count == 1 ? 401 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}

final class AsyncRetrierTests: XCTestCase {

    private let network = NetworkingClient(baseURL: "https://retrier.mocked.com")

    override func setUpWithError() throws {
        network.sessionConfiguration.protocolClasses = [UnauthorizedOnceURLProtocol.self]
        UnauthorizedOnceURLProtocol.authorizationHeaders = []
    }

    func testRetriedRequestSendsHeadersTheRetrierSet() async throws {
        network.headers["Authorization"] = "Bearer expired"
        network.asyncRequestRetrier = { [network] _, _, _ in
            // e.g. an auth token refresh
            network.headers["Authorization"] = "Bearer refreshed"
        }

        let _: Data = try await network.get("/users")

        XCTAssertEqual(UnauthorizedOnceURLProtocol.authorizationHeaders, ["Bearer expired", "Bearer refreshed"])
    }

    func testFailedRequestIsNotRetriedWithoutARetrier() async {
        network.headers["Authorization"] = "Bearer expired"

        do {
            let _: Data = try await network.get("/users")
            XCTFail("Expected the 401 to throw")
        } catch { }

        XCTAssertEqual(UnauthorizedOnceURLProtocol.authorizationHeaders, ["Bearer expired"])
    }
}
