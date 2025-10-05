//
//  Config.swift
//  WalkWorthy
//
//  Lightweight feature flag configuration.
//

import Foundation

struct Config {
    static let shared = Config()

    let apiMode: String
    let useFakeCanvas: Bool
    let notificationMode: String
    let defaultTranslation: Translation

    init(bundle: Bundle = .main) {
        var merged: [String: Any] = bundle.infoDictionary ?? [:]

        if let url = bundle.url(forResource: "Config", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            merged.merge(plist) { _, new in new }
        }

        apiMode = (merged["API_MODE"] as? String)?.lowercased() ?? "mock"
        useFakeCanvas = (merged["USE_FAKE_CANVAS"] as? NSNumber)?.boolValue ?? true
        notificationMode = (merged["NOTIFICATION_MODE"] as? String)?.lowercased() ?? "local"
        let translationKey = (merged["DEFAULT_TRANSLATION"] as? String)?.uppercased() ?? Translation.esv.rawValue
        defaultTranslation = Translation(rawValue: translationKey) ?? .esv
    }
}
