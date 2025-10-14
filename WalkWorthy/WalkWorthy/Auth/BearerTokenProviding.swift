//
//  BearerTokenProviding.swift
//  WalkWorthy
//
//  Abstraction used by networking layer to request Cognito JWTs.
//

import Foundation

protocol BearerTokenProviding {
    func validBearerToken() async throws -> String
}
