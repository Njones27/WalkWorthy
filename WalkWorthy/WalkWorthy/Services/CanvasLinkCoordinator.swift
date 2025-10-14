//
//  CanvasLinkCoordinator.swift
//  WalkWorthy
//
//  Handles the Canvas OAuth linking flow via ASWebAuthenticationSession.
//

import Foundation
import AuthenticationServices
import UIKit

@MainActor
final class CanvasLinkCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum CanvasLinkError: LocalizedError {
        case misconfigured
        case unableToStart
        case cancelled
        case missingAuthorization
        case backend(String?)

        var errorDescription: String? {
            switch self {
            case .misconfigured:
                return "Canvas configuration is incomplete."
            case .unableToStart:
                return "Unable to present Canvas sign-in."
            case .cancelled:
                return "Canvas linking was cancelled."
            case .missingAuthorization:
                return "Canvas did not return an authorization code."
            case .backend(let message):
                return message ?? "Failed to link Canvas."
            }
        }
    }

    private let config: Config
    private let authSession: AuthSession
    private let apiClient: LiveAPIClient
    private weak var anchorWindow: ASPresentationAnchor?
    private var webSession: ASWebAuthenticationSession?

    init(config: Config, authSession: AuthSession, apiClient: LiveAPIClient) {
        self.config = config
        self.authSession = authSession
        self.apiClient = apiClient
    }

    func startLink(from anchor: ASPresentationAnchor?) async throws -> Bool {
        guard let canvasBase = config.canvasBaseURL,
              let clientId = config.canvasClientId,
              let redirectURI = config.canvasRedirectURI else {
            throw CanvasLinkError.misconfigured
        }

        let sub = try await authSession.currentUserSub()
        let state = try buildState(sub: sub, canvasBaseURL: canvasBase, redirectURI: redirectURI)
        guard let authorizeURL = buildAuthorizeURL(
            baseURL: canvasBase,
            clientId: clientId,
            redirectURI: redirectURI,
            state: state
        ) else {
            throw CanvasLinkError.misconfigured
        }

        anchorWindow = anchor ?? firstAvailableAnchor()

        let callbackURL = try await performWebAuthentication(url: authorizeURL, callbackScheme: redirectURI.scheme)
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)

        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
            if error == "access_denied" {
                throw CanvasLinkError.cancelled
            }
            throw CanvasLinkError.backend(error)
        }

        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components?.queryItems?.first(where: { $0.name == "state" })?.value else {
            throw CanvasLinkError.missingAuthorization
        }

        let linked = try await apiClient.completeCanvasLink(code: code, state: returnedState, redirectURI: redirectURI)
        return linked
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let anchorWindow {
            return anchorWindow
        }
        if let fallback = firstAvailableAnchor() {
            self.anchorWindow = fallback
            return fallback
        }
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            return ASPresentationAnchor(windowScene: scene)
        }
        return UIWindow(frame: UIScreen.main.bounds)
    }

    // MARK: - Helpers

    private func buildState(sub: String, canvasBaseURL: URL, redirectURI: URL) throws -> String {
        let payload = CanvasStatePayload(
            userSub: sub,
            canvasBaseUrl: canvasBaseURL.absoluteString,
            redirectUri: redirectURI.absoluteString
        )
        let data = try JSONEncoder().encode(payload)
        return data.base64EncodedString()
    }

    private func buildAuthorizeURL(baseURL: URL, clientId: String, redirectURI: URL, state: String) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("login").appendingPathComponent("oauth2").appendingPathComponent("auth"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: "url:GET|/api/v1/users/self"),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    private func performWebAuthentication(url: URL, callbackScheme: String?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                self?.webSession = nil

                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CanvasLinkError.cancelled)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: CanvasLinkError.missingAuthorization)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self

            guard session.start() else {
                continuation.resume(throwing: CanvasLinkError.unableToStart)
                return
            }

            self.webSession = session
        }
    }

    private func firstAvailableAnchor() -> ASPresentationAnchor? {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return window
        }
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            return ASPresentationAnchor(windowScene: scene)
        }
        return nil
    }
}

private struct CanvasStatePayload: Codable {
    let userSub: String
    let canvasBaseUrl: String
    let redirectUri: String
}
