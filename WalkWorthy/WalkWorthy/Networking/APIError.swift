//
//  APIError.swift
//  WalkWorthy
//
//  Thin error wrapper for HTTP calls against the backend.
//

import Foundation

enum APIError: LocalizedError {
    case missingConfiguration(String)
    case unauthorized
    case notAuthenticated
    case conflict(message: String?)
    case server(statusCode: Int, message: String?)
    case decodingFailed(Error)
    case encodingFailed(Error)
    case network(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let key):
            return "Missing configuration value for \(key)."
        case .unauthorized, .notAuthenticated:
            return "Please sign in to continue."
        case .conflict(let message):
            return message ?? "Request could not be completed."
        case .server(_, let message):
            return message ?? "The server returned an unexpected error."
        case .decodingFailed:
            return "Failed to decode the server response."
        case .encodingFailed:
            return "Failed to encode the request payload."
        case .network(let error):
            return error.localizedDescription
        case .invalidResponse:
            return "Received an invalid response from the server."
        }
    }
}
