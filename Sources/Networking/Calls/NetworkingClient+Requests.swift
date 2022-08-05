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
        let req = NetworkingRequest(logger: self.logger)
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
            req?.sessionConfiguration = self.sessionConfiguration
            req?.timeout              = self.timeout
            req?.sessionDelegate      = self.sessionDelegate ?? nil 
        }
        updateRequest()
        req.requestRetrier = { [weak self] in
            self?.requestRetrier?($0, $1, $2)?
                .handleEvents(receiveOutput: { _ in
                    updateRequest()
                })
                .eraseToAnyPublisher()
        }
        return req
    }
}
