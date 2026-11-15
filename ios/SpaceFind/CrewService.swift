import CryptoKit
import Foundation
import Security

enum ConnectionIssue: LocalizedError {
    case invalidPairing, rejected, invalidResponse, storage(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidPairing: return "Paste the complete pairing string from the laptop."
        case .rejected: return "The laptop rejected the crew credentials. Check the invite on the laptop."
        case .invalidResponse: return "The laptop could not complete this request."
        case .storage(let status): return "Could not access crew credentials (\(status))."
        }
    }
}

struct Pairing {
    let url: URL
    let fingerprint: String
    let invite: String

    init(_ text: String) throws {
        struct Fields: Decodable { var url: String; var fingerprint: String; var invite: String }
        guard let fields = try? JSONDecoder().decode(Fields.self, from: Data(text.utf8)),
              let parts = URLComponents(string: fields.url),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.path.isEmpty || parts.path == "/", parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, let url = parts.url,
              fields.fingerprint.utf8.count == 64,
              fields.fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              !fields.invite.isEmpty else { throw ConnectionIssue.invalidPairing }
        self.url = url
        fingerprint = fields.fingerprint.lowercased()
        invite = fields.invite
    }
}

struct CrewCredentials: Codable {
    let url: URL
    let fingerprint: String
    let token: String

    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "SpaceFind.Crew",
        kSecAttrAccount as String: "current"
    ]

    static func load() throws -> Self? {
        var result: CFTypeRef?
        var request = query
        request[kSecReturnData as String] = true
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ConnectionIssue.storage(status) }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    func save() throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(self),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(Self.query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(Self.query.merging(attributes) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ConnectionIssue.storage(status) }
    }
}

private final class PinDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let fingerprint: String
    init(_ fingerprint: String) { self.fingerprint = fingerprint }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        // The invite supplies the laptop identity out of band, including for its self-signed certificate.
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
        if digest.map({ String(format: "%02x", $0) }).joined() == fingerprint {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class CrewService: CrewAPI {
    let credentials: CrewCredentials
    private let session: URLSession

    init(_ credentials: CrewCredentials) {
        self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config, delegate: PinDelegate(credentials.fingerprint), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    static func join(_ pairing: Pairing) async throws -> CrewService {
        struct Reply: Decodable { let token: String }
        let initial = CrewService(CrewCredentials(url: pairing.url, fingerprint: pairing.fingerprint, token: ""))
        let body = try JSONEncoder().encode(["invite": pairing.invite])
        let data = try await initial.request("join", body: body)
        let token = try JSONDecoder().decode(Reply.self, from: data).token
        guard !token.isEmpty else { throw ConnectionIssue.invalidResponse }
        return CrewService(CrewCredentials(url: pairing.url, fingerprint: pairing.fingerprint, token: token))
    }

    func fetch() async throws -> [Item] {
        struct Reply: Decodable { let items: [Item] }
        let data = try await request("inventory")
        return try JSONDecoder().decode(Reply.self, from: data).items
    }

    func send(_ change: Change) async throws {
        _ = try await request("changes", body: change.requestBody(), confirming: change.kind == .confirm)
    }

    private func request(_ path: String, body: Data? = nil, confirming: Bool = false) async throws -> Data {
        var request = URLRequest(url: credentials.url.appendingPathComponent(path))
        if !credentials.token.isEmpty {
            request.setValue("Bearer " + credentials.token, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ConnectionIssue.invalidResponse }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw ConnectionIssue.rejected
        case 409 where confirming: throw CrewError.staleConfirmation
        default: throw ConnectionIssue.invalidResponse
        }
    }
}
