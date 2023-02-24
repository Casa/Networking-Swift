//
//  NetworkingRequest.swift
//
//
//  Created by Sacha DSO on 21/02/2020.
//

import Foundation
import Combine

public typealias NetworkRequestRetrier = (_ request: URLRequest, _ error: Error, _ retryCount: Int) -> AnyPublisher<Void, Error>?
public typealias NetworkRequestRetrierAsync = (_ request: URLRequest, _ error: Error, _ retryCount: Int) async throws -> Void;

public class NetworkingRequest: NSObject {
    
    var parameterEncoding = ParameterEncoding.urlEncoded
    var baseURL = ""
    var route = ""
    var httpMethod = HTTPMethod.get
    public var params = Params()
    public var dataParams: Data?
    var headers = [String: String]()
    var multipartData: [MultipartData]?
    var logLevel: NetworkingLogLevel {
        get { return logger.logLevel }
        set { logger.logLevel = newValue }
    }
    private let logger: NetworkingLogger
    var timeout: TimeInterval?
    let progressPublisher = PassthroughSubject<Progress, Error>()
    var sessionConfiguration: URLSessionConfiguration?
    var sessionDelegate: URLSessionDelegate?
    var requestRetrier: NetworkRequestRetrier?
    var asyncRequestRetrier: NetworkRequestRetrierAsync?
    private let maxRetryCount = 3

    init(logger: NetworkingLogger = NetworkingLogger()) {
        self.logger = logger
    }

    public func uploadPublisher() -> AnyPublisher<(Data?, Progress), Error> {
        
        guard let urlRequest = buildURLRequest() else {
            return Fail(error: NetworkingError.unableToParseRequest as Error)
                .eraseToAnyPublisher()
        }
        logger.log(request: urlRequest)

        let config = sessionConfiguration ?? URLSessionConfiguration.default
        let sessionDelegate = sessionDelegate ?? self
        let urlSession = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        let callPublisher: AnyPublisher<(Data?, Progress), Error> = urlSession.dataTaskPublisher(for: urlRequest)
            .tryMap { (data: Data, response: URLResponse) -> Data in
                self.logger.log(response: response, data: data)
                if let httpURLResponse = response as? HTTPURLResponse {
                    if !(200...299 ~= httpURLResponse.statusCode) {
                        var error = NetworkingError(errorCode: httpURLResponse.statusCode)
                        if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                            error.jsonPayload = json
                        }
                        throw error
                    }
                }
                return data
            }.mapError { error -> NetworkingError in
                return NetworkingError(error: error)
            }.map { data -> (Data?, Progress) in
                return (data, Progress())
            }.eraseToAnyPublisher()
        
        let progressPublisher2: AnyPublisher<(Data?, Progress), Error> = progressPublisher
            .map { progress -> (Data?, Progress) in
                return (nil, progress)
            }.eraseToAnyPublisher()
        
        return Publishers.Merge(callPublisher, progressPublisher2)
            .receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    public func publisher() -> AnyPublisher<Data, Error> {
        publisher(retryCount: maxRetryCount)
    }

    private func publisher(retryCount: Int) -> AnyPublisher<Data, Error> {
        guard let urlRequest = buildURLRequest() else {
            return Fail(error: NetworkingError.unableToParseRequest as Error)
                .eraseToAnyPublisher()
        }
        logger.log(request: urlRequest)

        let config = sessionConfiguration ?? URLSessionConfiguration.default
        let sessionDelegate = sessionDelegate ?? self
        let urlSession = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        return urlSession.dataTaskPublisher(for: urlRequest)
            .tryMap { (data: Data, response: URLResponse) -> Data in
                self.logger.log(response: response, data: data)
                if let httpURLResponse = response as? HTTPURLResponse {
                    if !(200...299 ~= httpURLResponse.statusCode) {
                        var error = NetworkingError(errorCode: httpURLResponse.statusCode)
                        if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                            error.jsonPayload = json
                        }
                        throw error
                    }
                }
                return data
            }.tryCatch({ [weak self] error -> AnyPublisher<Data, Error> in
                guard
                    let self = self,
                    retryCount >= 1,
                    let retryPublisher = self.requestRetrier?(urlRequest, error, retryCount)
                else {
                    throw error
                }
                return retryPublisher
                    .flatMap { _ -> AnyPublisher<Data, Error> in
                        self.publisher(retryCount: retryCount - 1)
                    }
                    .eraseToAnyPublisher()
            }).mapError { error -> NetworkingError in
                return NetworkingError(error: error)
            }.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    public func execute() async throws -> Data {
        try await execute(retryCount: maxRetryCount)
    }
    
    private func execute(retryCount: Int) async throws -> Data {
        guard let urlRequest = buildURLRequest() else {
            throw NetworkingError.unableToParseRequest
        }
        logger.log(request: urlRequest)
        let config = sessionConfiguration ?? URLSessionConfiguration.default
        let sessionDelegate = sessionDelegate ?? self
        let urlSession = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)

        let (data, urlResponse) = try await urlSession.data(for: urlRequest)
        if let httpResponse = urlResponse as? HTTPURLResponse,
            !(200...299 ~= httpResponse.statusCode) {
                logger.log(response: httpResponse, data: data)
                var error = NetworkingError(errorCode: httpResponse.statusCode)
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                    error.jsonPayload = json
                }

                if retryCount >= 1,
                    let asyncRetrier = self.asyncRequestRetrier {
                    _ = try await asyncRetrier(urlRequest, error, retryCount)

                    return try await execute(retryCount: retryCount - 1)
                }

                throw error
            }

        logger.log(response: urlResponse, data: data)
        return data;
    }
    
    private func getURLWithParams() -> String {
        let urlString = baseURL + route
        if params.isEmpty { return urlString }
        guard let url = URL(string: urlString) else {
            return urlString
        }
        if var urlComponents = URLComponents(url: url ,resolvingAgainstBaseURL: false) {
            var queryItems = urlComponents.queryItems ?? [URLQueryItem]()
            params.forEach { param in
                // arrayParam[] syntax
                if let array = param.value as? [CustomStringConvertible] {
                    array.forEach {
                        queryItems.append(URLQueryItem(name: "\(param.key)[]", value: "\($0)"))
                    }
                }
                queryItems.append(URLQueryItem(name: param.key, value: "\(param.value)"))
            }
            urlComponents.queryItems = queryItems
            return urlComponents.url?.absoluteString ?? urlString
        }
        return urlString
    }
    
    internal func buildURLRequest() -> URLRequest? {
        var urlString = baseURL + route
        if httpMethod == .get {
            urlString = getURLWithParams()
        }
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        var request = URLRequest(url: url)
        
        if httpMethod != .get && multipartData == nil {
            switch parameterEncoding {
            case .urlEncoded:
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            case .json:
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        
        request.httpMethod = httpMethod.rawValue
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let timeout = timeout {
            request.timeoutInterval = timeout
        }
        
        if httpMethod != .get && multipartData == nil {
            switch parameterEncoding {
            case .urlEncoded:
                request.httpBody = params.asPercentEncodedString().data(using: .utf8)
            case .json:
                if let dataParams = dataParams {
                    request.httpBody = dataParams
                } else {
                    let jsonData = try? JSONSerialization.data(withJSONObject: params)
                    request.httpBody = jsonData
                }
            }
        }
        
        // Multipart
        if let multiparts = multipartData {
            // Construct a unique boundary to separate values
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = buildMultipartHttpBody(params: params, multiparts: multiparts, boundary: boundary)
        }
        return request
    }
    
    private func buildMultipartHttpBody(params: Params, multiparts: [MultipartData], boundary: String) -> Data {
        // Combine all multiparts together
        let allMultiparts: [HttpBodyConvertible] = [params] + multiparts
        let boundaryEnding = "--\(boundary)--".data(using: .utf8)!
        
        // Convert multiparts to boundary-seperated Data and combine them
        return allMultiparts
            .map { (multipart: HttpBodyConvertible) -> Data in
                return multipart.buildHttpBodyPart(boundary: boundary)
            }
            .reduce(Data.init(), +)
            + boundaryEnding
    }
}

// Thansks to https://stackoverflow.com/questions/26364914/http-request-in-swift-with-post-method
extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")
        return allowed
    }()
}

extension NetworkingRequest: URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didSendBodyData bytesSent: Int64,
                           totalBytesSent: Int64,
                           totalBytesExpectedToSend: Int64) {
        let progress = Progress(totalUnitCount: totalBytesExpectedToSend)
        progress.completedUnitCount = totalBytesSent
        progressPublisher.send(progress)
    }
}

public enum ParameterEncoding {
    case urlEncoded
    case json
}

@available(iOS, deprecated: 15.0, message: "Use the built-in API instead")
extension URLSession {
    func data(for urlRequest: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: urlRequest) { data, response, error in
                guard let data = data, let response = response else {
                    let error = error ?? URLError(.badServerResponse)
                    return continuation.resume(throwing: error)
                }

                continuation.resume(returning: (data, response))
            }

            task.resume()
        }
    }
}
