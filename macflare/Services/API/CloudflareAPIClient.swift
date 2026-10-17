//
//  CloudflareAPIClient.swift
//  macflare
//
//  Thin REST client that injects the OAuth bearer token.
//

import Foundation

struct CloudflareAccount: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
    }
}

enum CloudflareAPIError: Error, LocalizedError, Equatable {
    case unauthorized
    case forbidden
    case httpStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Cloudflare rejected your session. Please sign in again."
        case .forbidden:
            return "Cloudflare denied access to your accounts. Check the app's account.read permission and your account access, then retry."
        case .httpStatus(let status):
            return "Cloudflare could not load your accounts (status \(status)). Please retry."
        case .invalidResponse:
            return "Cloudflare returned an invalid account response. Please retry."
        }
    }
}

/// Sends bearer credentials only to the configured API endpoint. A rejected
/// token is refreshed once; permission errors do not discard the session.
@MainActor
struct CloudflareAPIClient {
    let tokenProvider: @MainActor () async throws -> String
    var session: URLSession = .shared
    var baseURL: URL = CloudflareOAuthConfig.live.apiBaseURL
    var refreshToken: (@MainActor (String) async throws -> String)?
    var invalidateToken: (@MainActor (String) -> Void)?

    func loadAccounts() async throws -> [CloudflareAccount] {
        var accounts: [CloudflareAccount] = []
        var page = 1
        while true {
            var components = URLComponents(url: baseURL.appendingPathComponent("accounts"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: "50"),
            ]
            let data = try await get(components.url!)
            let response: AccountsResponse
            do {
                response = try JSONDecoder().decode(AccountsResponse.self, from: data)
            } catch {
                throw CloudflareAPIError.invalidResponse
            }
            guard response.success != false, let result = response.result else {
                throw CloudflareAPIError.invalidResponse
            }
            accounts.append(contentsOf: result)
            guard let totalPages = response.resultInfo?.totalPages, page < totalPages else { break }
            // Bound malformed pagination instead of looping forever.
            guard page < 1_000 else { throw CloudflareAPIError.invalidResponse }
            page += 1
        }
        return accounts
    }

    @discardableResult
    func verifyToken() async throws -> [String] {
        try await loadAccounts().map(\.id)
    }

    private static func isRejectedBearer(status: Int, data: Data) -> Bool {
        guard status == 403 else { return false }
        struct ErrorEnvelope: Decodable {
            struct APIError: Decodable { let code: Int; let message: String? }
            let errors: [APIError]
        }
        // Cloudflare also uses 9109 for missing resource permissions, so the
        // code alone is insufficient evidence that a session was rejected.
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?
            .errors.contains(where: {
                $0.code == 9109 && $0.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "invalid access token"
            }) == true
    }

    private func get(_ url: URL) async throws -> Data {
        var bearer = try await tokenProvider()
        for attempt in 0...1 {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CloudflareAPIError.invalidResponse }
            if http.statusCode == 401 || Self.isRejectedBearer(status: http.statusCode, data: data) {
                if attempt == 0, let refreshToken {
                    bearer = try await refreshToken(bearer)
                    continue
                }
                invalidateToken?(bearer)
                throw CloudflareAPIError.unauthorized
            }
            switch http.statusCode {
            case 200..<300: return data
            case 403: throw CloudflareAPIError.forbidden
            default: throw CloudflareAPIError.httpStatus(http.statusCode)
            }
        }
        throw CloudflareAPIError.unauthorized
    }
}

private struct AccountsResponse: Decodable {
    struct ResultInfo: Decodable {
        let totalPages: Int?
        enum CodingKeys: String, CodingKey { case totalPages = "total_pages" }
    }
    let success: Bool?
    let result: [CloudflareAccount]?
    let resultInfo: ResultInfo?
    enum CodingKeys: String, CodingKey {
        case success, result
        case resultInfo = "result_info"
    }
}
