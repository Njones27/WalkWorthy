//
//  MockAPIClient.swift
//  WalkWorthy
//
//  Loads mock JSON responses from the bundle.
//

import Foundation

struct MockAPIClient: EncouragementAPI {
    private let decoder: JSONDecoder
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchNext() async throws -> NextResponse {
        try await load(named: "encouragement_next", type: NextResponse.self)
    }

    func fetchTodayCanvas() async throws -> TodayCanvas {
        try await load(named: "today_canvas", type: TodayCanvas.self)
    }

    private func load<T: Decodable>(named name: String, type: T.Type) async throws -> T {
        try await Task.sleep(nanoseconds: 150_000_000) // Simulate network latency
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Mock") else {
            throw MockAPIError.missingResource(name)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    enum MockAPIError: LocalizedError {
        case missingResource(String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                return "Mock resource \(name) was not found in the bundle."
            }
        }
    }
}
