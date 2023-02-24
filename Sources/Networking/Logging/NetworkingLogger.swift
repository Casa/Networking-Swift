//
//  NetworkingLogger.swift
//
//
//  Created by Sacha on 13/03/2020.
//

import Foundation

class NetworkingLogger {

    var logLevel = NetworkingLogLevel.off
    let filteredWords: [String]

    init(filteredWords: [String] = []) {
        self.filteredWords = filteredWords
    }

    func log(request: URLRequest) {
        // If nil, it means that our .logLevel is .off
        if let logString = requestLogString(request: request) {
            print(logString)
        } else {
            return
        }
    }

    func log(response: URLResponse, data: Data) {
        // If nil, it means that our .logLevel is .off
        if let logString = responseLogString(response: response, data: data) {
            print(logString)
        } else {
            return
        }
    }

    internal func responseLogString(response: URLResponse, data: Data) -> String? {
        guard logLevel != .off else {
            return nil
        }
        var log = "----- HTTP Response -----\n"

        if let response = response as? HTTPURLResponse {
            log += logStatusCodeAndURL(response)
        }
        
        log += String(decoding: data, as: UTF8.self)

        return log
    }

     func requestLogString(request: URLRequest) -> String? {
        guard logLevel != .off else {
            return nil
        }
        var log = "----- HTTP Request -----\n"

        if let method = request.httpMethod,
            let url = request.url {
            log += "\(method) to '\(url.absoluteString)'\n"
            log += logHeaders(request)
            log += logBody(request)
        }
        if logLevel == .debug {
            log += request.toCurlCommand()
        }

        return log
    }

    private func logStatusCodeAndURL(_ urlResponse: HTTPURLResponse) -> String {
        if let url = urlResponse.url {
            return "\(urlResponse.statusCode) from '\(url.absoluteString)'\n"
        }
        return ""
    }

    private func logHeaders(_ urlRequest: URLRequest) -> String {
        var log = "HEADERS:\n"
        if let allHTTPHeaderFields = urlRequest.allHTTPHeaderFields {
            for (key, value) in allHTTPHeaderFields {
                if filteredWords.contains(key) {
                    log += "\(key) : [FILTERED]\n"
                } else {
                    log += "\(key) : \(value)\n"
                }
            }
        }
        return log
    }

    private func logBody(_ urlRequest: URLRequest) -> String {
        var log = "BODY:\n"
        if let body = urlRequest.httpBody,
            let str = String(data: body, encoding: .utf8) {
            
            if filteredWords.count > 0 {
                str = str.filtered(sensitiveWords: filteredWords)
            }
            
            log += "\(str)\n"
        }
        return log
    }
}

// MARK: String helpers
extension String
{
    func filtered(sensitiveWords: [String]) -> String
    {
        var filterSearchRegex = ""
        for word in sensitiveWords
        {
            filterSearchRegex.append(word)
            if word != sensitiveWords.last
            {
                filterSearchRegex.append("|")
            }
        }
        
        let regexExpression = String(format: "\"(%@)\" *: *[^,}]*", filterSearchRegex)
        if let regex = try? NSRegularExpression(pattern: regexExpression, options: .caseInsensitive)
        {
            //let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: string.length))
            return regex.stringByReplacingMatches(in: self, options: [], range: NSRange(location: 0, length: self.count), withTemplate: "$1: [FILTERED]")
        }
        
        return self
    }
}

extension URLRequest {

    /**
        Heavily inspired from : https://gist.github.com/shaps80/ba6a1e2d477af0383e8f19b87f53661d
     */
    public func toCurlCommand() -> String {
        guard let url = url else { return "" }
        var command = ["curl \"\(url.absoluteString)\""]

        if let method = httpMethod, method != "GET" && method != "HEAD" {
            command.append("-X \(method)")
        }

        allHTTPHeaderFields?
            .filter { $0.key != "Cookie" }
            .forEach { command.append("-H '\($0.key): \($0.value)'")}

        if let data = httpBody, let body = String(data: data, encoding: .utf8) {
            command.append("-d '\(body)'")
        }

        return command.joined(separator: " \\\n\t")
    }

}
