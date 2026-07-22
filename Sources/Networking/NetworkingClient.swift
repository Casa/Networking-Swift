import Foundation
import Combine

public class NetworkingClient {
    /**
        Instead of using the same keypath for every call eg: "collection",
        this enables to use a default keypath for parsing collections.
        This is overridden by the per-request keypath if present.
     
     */
    public var defaultCollectionParsingKeyPath: String?
    let baseURL: String

    // Headers are read on every request build (including retries on URLSession/Combine
    // threads) and mutated on auth token refresh from arbitrary threads. Dictionary is
    // not thread-safe, so all access goes through a lock. The public property keeps the
    // same get/set surface as the previous stored `var`.
    private let headersLock = NSLock()
    private var _headers = [String: String]()
    public var headers: [String: String] {
        get {
            headersLock.lock()
            defer { headersLock.unlock() }
            return _headers
        }
        set {
            headersLock.lock()
            defer { headersLock.unlock() }
            _headers = newValue
        }
    }

    /**
        Atomically reads and mutates the headers dictionary under the same lock that
        protects the `headers` property. Use this instead of get-modify-set on `headers`
        when the modification must not race with other writers (e.g. merging auth headers).
        Do not access `headers` or call `withHeaders` again from inside `body` — the lock
        is not reentrant.
    */
    @discardableResult
    public func withHeaders<T>(_ body: (inout [String: String]) -> T) -> T {
        headersLock.lock()
        defer { headersLock.unlock() }
        return body(&_headers)
    }

    public var parameterEncoding = ParameterEncoding.urlEncoded
    public var timeout: TimeInterval?
    public var sessionConfiguration = URLSessionConfiguration.default
    public var sessionDelegate: URLSessionDelegate?
    public var requestRetrier: NetworkRequestRetrier?
    public var asyncRequestRetrier: NetworkRequestRetrierAsync?
    public var jsonDecoderFactory: (() -> JSONDecoder)?

    /**
        Prints network calls to the console.
        Values Available are .None, Calls and CallsAndResponses.
        Default is None
    */
    public var logLevel: NetworkingLogLevel {
        get { return logger.logLevel }
        set { logger.logLevel = newValue }
    }

    internal let logger: NetworkingLogger 
    
    // URLSession is created lazily and reused for all requests from this client
    // The session is shared by reference with all NetworkingRequest instances,
    // so it remains alive as long as any requests are using it
    internal lazy var urlSession: URLSession = {
        let config = sessionConfiguration
        let delegate = sessionDelegate
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    public init(baseURL: String, timeout: TimeInterval? = nil, filteredWords: [String] = []) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.logger = NetworkingLogger(filteredWords: filteredWords)
    }
    
    public func toModel<T: NetworkingJSONDecodable>(_ json: Any, keypath: String? = nil) throws -> T {
        do {
            let data = resourceData(from: json, keypath: keypath)
            return try T.decode(data)
        } catch (let error) {
            throw error
        }
    }
    
    public func toModel<T: Decodable>(_ json: Any, keypath: String? = nil) throws -> T {
        do {
            let jsonObject = resourceData(from: json, keypath: keypath)
            let decoder = jsonDecoderFactory?() ?? JSONDecoder()
            let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
            let model = try decoder.decode(T.self, from: data)
            return model
        } catch (let error) {
            throw error
        }
    }

    public func toModels<T: NetworkingJSONDecodable>(_ json: Any, keypath: String? = nil) throws -> [T] {
        do {
            guard let array = resourceData(from: json, keypath: keypath) as? [Any] else {
                return [T]()
            }
            return try array.map {
                try T.decode($0)
            }.compactMap { $0 }
        } catch (let error) {
            throw error
        }
    }
    
    public func toModels<T: Decodable>(_ json: Any, keypath: String? = nil) throws -> [T] {
        do {
            guard let array = resourceData(from: json, keypath: keypath) as? [Any] else {
                return [T]()
            }
            return try array.map { jsonObject in
                let decoder = jsonDecoderFactory?() ?? JSONDecoder()
                let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
                let model = try decoder.decode(T.self, from: data)
                return model
            }.compactMap { $0 }
        } catch (let error) {
            throw error
        }
    }

    private func resourceData(from json: Any, keypath: String?) -> Any {
        if let keypath = keypath, !keypath.isEmpty, let dic = json as? [String: Any], let val = dic[keypath] {
            return val is NSNull ? json : val
        }
        return json
    }
}

