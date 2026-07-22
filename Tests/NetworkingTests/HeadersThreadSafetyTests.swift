//
//  HeadersThreadSafetyTests.swift
//
//  Regression tests for the data race on NetworkingClient.headers that caused
//  EXC_BAD_ACCESS / EXC_BREAKPOINT / SIGABRT crashes in production when auth
//  header updates raced with request building on other threads.
//

import Foundation
import XCTest

@testable
import Networking

final class HeadersThreadSafetyTests: XCTestCase {

    // Hammers the same access pattern that crashed in production:
    // writers doing get-modify-set add/remove cycles (auth token refresh) while
    // readers copy the dictionary (request building). Before headers was
    // lock-protected this reliably corrupted the dictionary's CoW buffer.
    func testConcurrentReadsAndWritesDoNotCrash() {
        let network = NetworkingClient(baseURL: "https://mocked.com")
        network.headers = ["Client-Version": "1.0.0", "Client-OS": "iOS"]

        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        let iterations = 2_000

        // writers: replace auth headers, like setAuthHeaders on token refresh
        for writer in 0..<4 {
            queue.async(group: group) {
                for i in 0..<iterations {
                    var copy = network.headers
                    copy.removeValue(forKey: "Authorization")
                    network.headers = copy
                    network.headers = network.headers.merging(
                        ["Authorization": "Bearer token-\(writer)-\(i)"]) { _, new in new }
                }
            }
        }

        // readers: copy headers into a request, like NetworkingClient+Requests
        for _ in 0..<4 {
            queue.async(group: group) {
                for _ in 0..<iterations {
                    let snapshot = network.headers
                    _ = snapshot.count
                }
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)
        XCTAssertEqual(network.headers["Client-OS"], "iOS")
    }

    // withHeaders must be atomic: concurrent read-modify-writes through it must
    // never lose updates, which get-modify-set on the plain property can.
    func testWithHeadersIsAtomic() {
        let network = NetworkingClient(baseURL: "https://mocked.com")
        network.headers = ["counter": "0"]

        let totalIncrements = 8_000
        DispatchQueue.concurrentPerform(iterations: totalIncrements) { _ in
            network.withHeaders { headers in
                let current = Int(headers["counter"] ?? "0") ?? 0
                headers["counter"] = String(current + 1)
            }
        }

        XCTAssertEqual(network.headers["counter"], String(totalIncrements))
    }

    // The property must keep behaving like the stored `var` it replaced.
    func testHeadersPropertyKeepsValueSemantics() {
        let network = NetworkingClient(baseURL: "https://mocked.com")

        network.headers["a"] = "1"
        XCTAssertEqual(network.headers["a"], "1")

        var snapshot = network.headers
        snapshot["b"] = "2"
        XCTAssertNil(network.headers["b"], "mutating a copy must not affect the client")

        network.headers = [:]
        XCTAssertTrue(network.headers.isEmpty)

        let returned = network.withHeaders { headers -> Int in
            headers["c"] = "3"
            return headers.count
        }
        XCTAssertEqual(returned, 1)
        XCTAssertEqual(network.headers["c"], "3")
    }
}
