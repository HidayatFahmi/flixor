//
//  APIClient.swift
//  FlixorMac
//
//  API client for communicating with backend
//

import Foundation

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    @Published var isAuthenticated = false

    var baseURL: URL
    private var session: URLSession
    private var token: String?

    init() {
        // Load base URL from UserDefaults or use default
        let baseURLString = UserDefaults.standard.string(forKey: "backendBaseURL") ?? "http://localhost:3001"
        self.baseURL = URL(string: baseURLString)!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        // Load token from keychain
        self.token = KeychainHelper.shared.getToken()
        self.isAuthenticated = (token != nil)
    }

    // MARK: - Configuration

    func setBaseURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        self.baseURL = url
        UserDefaults.standard.set(urlString, forKey: "backendBaseURL")
    }

    func setToken(_ token: String?) {
        self.token = token
        self.isAuthenticated = (token != nil)

        if let token = token {
            KeychainHelper.shared.saveToken(token)
        } else {
            KeychainHelper.shared.deleteToken()
        }
    }

    // MARK: - Request Methods

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil, bypassCache: Bool = false) async throws -> T {
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Bypass cache for critical requests (e.g., metadata with part keys)
        if bypassCache {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        }

        addHeaders(to: &request)

        return try await performRequest(request)
    }

    func post<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        return try await performRequest(request)
    }

    func put<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        addHeaders(to: &request)

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        return try await performRequest(request)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addHeaders(to: &request)

        return try await performRequest(request)
    }

    // MARK: - Private Helpers

    private func addHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        // Log request
        let cachePolicy = request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData ? " [BYPASS CACHE]" : ""
        print("🌐 [API] \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")\(cachePolicy)")
        if let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems {
            print("   Query: \(queryItems.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", "))")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [API] Invalid response type")
                throw APIError.serverError("Invalid response")
            }

            print("📡 [API] Response: \(httpResponse.statusCode)")

            // Check status code
            switch httpResponse.statusCode {
            case 200...299:
                // Success
                if let responseString = String(data: data, encoding: .utf8) {
                    print("✅ [API] Response body: \(responseString.prefix(200))...")
                }
                break
            case 401:
                // Unauthorized - clear token
                print("🔐 [API] Unauthorized (401) - clearing token")
                await MainActor.run {
                    setToken(nil)
                }
                throw APIError.unauthorized
            case 400...499:
                // Client error
                let message = try? JSONDecoder().decode([String: String].self, from: data)
                print("⚠️ [API] Client error (\(httpResponse.statusCode)): \(message?["message"] ?? message?["error"] ?? "unknown")")
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: message?["message"] ?? message?["error"])
            case 500...599:
                // Server error
                let message = try? JSONDecoder().decode([String: String].self, from: data)
                print("❌ [API] Server error (\(httpResponse.statusCode)): \(message?["message"] ?? message?["error"] ?? "unknown")")
                throw APIError.serverError(message?["message"] ?? message?["error"] ?? "Unknown server error")
            default:
                print("❌ [API] Unexpected status code: \(httpResponse.statusCode)")
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
            }

            // Decode response
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .useDefaultKeys
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(T.self, from: data)
                print("✅ [API] Successfully decoded response")
                return decoded
            } catch {
                print("❌ [API] Decoding error: \(error)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("   Raw response: \(responseString.prefix(500))")
                }
                throw APIError.decodingError(error)
            }

        } catch let error as APIError {
            throw error
        } catch {
            print("❌ [API] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }

    // MARK: - Health Check

    func healthCheck() async throws -> [String: String] {
        let healthURL = baseURL.deletingLastPathComponent().appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError("Health check failed")
        }

        return try JSONDecoder().decode([String: String].self, from: data)
    }

    // MARK: - Plex Server Methods

    func getPlexServers() async throws -> [PlexServer] {
        return try await get("/api/plex/servers")
    }

    func getPlexConnections(serverId: String) async throws -> PlexConnectionsResponse {
        let encodedId = serverId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? serverId
        return try await get("/api/plex/servers/\(encodedId)/connections")
    }

    func getPlexAuthServers() async throws -> [PlexAuthServer] {
        return try await get("/api/auth/servers")
    }

    func setCurrentPlexServer(serverId: String) async throws -> SimpleMessageResponse {
        struct Body: Encodable { let serverId: String }
        return try await post("/api/plex/servers/current", body: Body(serverId: serverId))
    }

    func setPlexServerEndpoint(serverId: String, uri: String, test: Bool = true) async throws -> PlexEndpointUpdateResponse {
        struct Body: Encodable { let uri: String; let test: Bool }
        let encodedId = serverId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? serverId
        return try await post("/api/plex/servers/\(encodedId)/endpoint", body: Body(uri: uri, test: test))
    }

    func traktDeviceCode() async throws -> TraktDeviceCodeResponse {
        return try await post("/api/trakt/oauth/device/code")
    }

    func traktDeviceToken(code: String) async throws -> TraktTokenPollResponse {
        struct Body: Encodable { let code: String }
        return try await post("/api/trakt/oauth/device/token", body: Body(code: code))
    }

    func traktUserProfile() async throws -> TraktUserProfile {
        return try await get("/api/trakt/users/me")
    }

    func traktSignOut() async throws -> SimpleOkResponse {
        return try await post("/api/trakt/signout")
    }
}

// MARK: - Plex Markers (intro/credits)

struct PlexMarkersEnvelope: Decodable {
    let MediaContainer: PlexMarkersContainer?
}

struct PlexMarkersContainer: Decodable {
    let Metadata: [PlexMarkersMetadata]?
}

struct PlexMarkersMetadata: Decodable {
    let Marker: [PlexMarker]?
}

struct PlexMarker: Decodable {
    let id: String?
    let type: String?
    let startTimeOffset: Int?
    let endTimeOffset: Int?
}

extension APIClient {
    /// Fetch Plex intro/credits markers for a ratingKey.
    func getPlexMarkers(ratingKey: String) async throws -> [PlexMarker] {
        let encoded = ratingKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ratingKey
        let path = "/api/plex/dir/library/metadata/\(encoded)"
        let env: PlexMarkersEnvelope = try await get(path, queryItems: [URLQueryItem(name: "includeMarkers", value: "1")])
        let list = env.MediaContainer?.Metadata?.first?.Marker ?? []
        return list
    }
}

// MARK: - Supporting Models

struct SimpleMessageResponse: Decodable {
    let message: String?
    let serverId: String?
}

struct SimpleOkResponse: Decodable {
    let ok: Bool
    let message: String?
}

struct PlexEndpointUpdateResponse: Decodable {
    let message: String?
    let server: PlexEndpointServer?
}

struct PlexEndpointServer: Decodable {
    let id: String?
    let host: String?
    let port: Int?
    let protocolName: String?
    let preferredUri: String?

    enum CodingKeys: String, CodingKey {
        case id
        case host
        case port
        case preferredUri
        case protocolName = "protocol"
    }
}

struct TraktDeviceCodeResponse: Decodable {
    let device_code: String
    let user_code: String
    let verification_url: String
    let expires_in: Int
    let interval: Int?
}

struct TraktTokenPollResponse: Decodable {
    let ok: Bool
    let tokens: [String: String]?
    let error: String?
    let error_description: String?
}

struct TraktUserProfile: Decodable {
    struct IDs: Decodable { let slug: String? }
    let username: String?
    let name: String?
    let ids: IDs?
}
