//
//  NetworkingClient+Requests.swift
//
//
//  Created by Sacha on 13/03/2020.
//

import Foundation
import Combine

public extension NetworkingClient {

    func getRequest(_ route: String, params: Params = Params()) -> NetworkingRequest {
        request(.get, route, params: params)
    }

    func postRequest(_ route: String, params: Params = Params()) -> NetworkingRequest {
        request(.post, route, params: params)
    }

    func putRequest(_ route: String, params: Params = Params()) -> NetworkingRequest {
        request(.put, route, params: params)
    }
    
    func patchRequest(_ route: String, params: Params = Params()) -> NetworkingRequest {
        request(.patch, route, params: params)
    }

    func deleteRequest(_ route: String, params: Params = Params()) -> NetworkingRequest {
        request(.delete, route, params: params)
    }

    internal func request(_ httpMethod: HTTPMethod, _ route: String, params: Params = Params(), data: Data? = nil) -> NetworkingRequest {
        let req = NetworkingRequest(logger: self.logger, urlSession: self.urlSession)
        req.httpMethod             = httpMethod
        req.route                = route
        req.params               = params
        req.dataParams           = data

        let updateRequest = { [weak req, weak self] in
            guard let self = self else { return }
            req?.baseURL              = self.baseURL
            req?.logLevel             = self.logLevel
            req?.headers              = self.headers
            req?.parameterEncoding    = self.parameterEncoding
            req?.timeout              = self.timeout
        }
        updateRequest()
        req.requestRetrier = { [weak self] in
            self?.requestRetrier?($0, $1, $2)?
                .handleEvents(receiveOutput: { _ in
                    updateRequest()
                })
                .eraseToAnyPublisher()
        }

        req.asyncRequestRetrier = updateAndRetryAsync(updateRequest: { updateRequest() }, request: self.asyncRequestRetrier)
        return req
    }

    // Wrap NetworkRequestRetrierAsync so the request copies the client's current headers (and other
    // settings) after the retrier finishes. A retrier that refreshes an auth token sets new headers
    // on the client; the retried request must send them, not the headers it was first built with.
    private func updateAndRetryAsync(updateRequest: @escaping () -> (), request: NetworkRequestRetrierAsync?) -> NetworkRequestRetrierAsync? {
        guard let request = request else {
            return nil
        }
        return { urlRequest, error, retryCount in
            try await request(urlRequest, error, retryCount)
            updateRequest()
        }
    }
}
