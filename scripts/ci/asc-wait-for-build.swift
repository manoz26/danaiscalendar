// Waits until App Store Connect has processed an uploaded build, and reports its state.
//
// Build: swiftc -swift-version 5 -parse-as-library scripts/ci/asc-wait-for-build.swift -o build/asc-wait-for-build
// Usage: build/asc-wait-for-build <bundle-id> <version> <build-number>
// Env:   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID (App Store Connect API key)
//
// Exit 0 when the build is VALID (or still processing at the time limit, with a warning),
// 1 when App Store Connect rejected it or the API failed.
import CryptoKit
import Foundation

struct APIError: Error, CustomStringConvertible {
    let description: String
}

struct AppStoreConnect {
    let keyID: String
    let issuerID: String
    let keyPEM: String

    /// Short-lived ES256 token for the App Store Connect API.
    func token() throws -> String {
        let key = try P256.Signing.PrivateKey(pemRepresentation: keyPEM)
        let now = Int(Date().timeIntervalSince1970)
        let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"])
        let claims = try JSONSerialization.data(withJSONObject: [
            "iss": issuerID, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1",
        ] as [String: Any])
        let signingInput = Self.base64URL(header) + "." + Self.base64URL(claims)
        let signature = try key.signature(for: Data(signingInput.utf8))
        return signingInput + "." + Self.base64URL(signature.rawRepresentation)
    }

    func get(_ path: String, _ query: [(String, String)]) async throws -> [String: Any] {
        var components = URLComponents(string: "https://api.appstoreconnect.apple.com" + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw APIError(description: "GET \(path) → HTTP \(status): \(String(decoding: data, as: UTF8.self))")
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

@main
struct WaitForBuild {
    static let timeLimit: TimeInterval = 25 * 60
    static let pollSeconds: UInt64 = 30

    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            print("usage: asc-wait-for-build <bundle-id> <version> <build-number>")
            exit(2)
        }
        let (bundleID, version, buildNumber) = (arguments[1], arguments[2], arguments[3])

        do {
            let api = AppStoreConnect(
                keyID: try environment("ASC_KEY_ID"),
                issuerID: try environment("ASC_ISSUER_ID"),
                keyPEM: try String(contentsOfFile: environment("ASC_KEY_PATH"), encoding: .utf8)
            )

            let apps = try await api.get("/v1/apps", [("filter[bundleId]", bundleID), ("fields[apps]", "bundleId,name")])
            let appList = apps["data"] as? [[String: Any]] ?? []
            guard let app = appList.first(where: {
                ($0["attributes"] as? [String: Any])?["bundleId"] as? String == bundleID
            }), let appID = app["id"] as? String else {
                throw APIError(description: "No App Store Connect app with bundle id \(bundleID)")
            }
            print("App Store Connect app id: \(appID)")

            let deadline = Date().addingTimeInterval(timeLimit)
            var lastState = ""
            while Date() < deadline {
                let builds = try await api.get("/v1/builds", [
                    ("filter[app]", appID),
                    ("filter[version]", buildNumber),
                    ("filter[preReleaseVersion.version]", version),
                    ("include", "buildBetaDetail"),
                    ("limit", "1"),
                ])
                let build = (builds["data"] as? [[String: Any]])?.first
                let attributes = build?["attributes"] as? [String: Any] ?? [:]
                let state = attributes["processingState"] as? String ?? "NOT_VISIBLE_YET"
                let beta = (builds["included"] as? [[String: Any]])?
                    .first { $0["type"] as? String == "buildBetaDetails" }?["attributes"] as? [String: Any]
                let internalState = beta?["internalBuildState"] as? String ?? "-"

                if state != lastState {
                    print("\(Date()): build \(version) (\(buildNumber)) is \(state), TestFlight internal: \(internalState)")
                    lastState = state
                }
                switch state {
                case "VALID":
                    print("Build \(version) (\(buildNumber)) is processed. TestFlight internal state: \(internalState)")
                    if internalState == "MISSING_EXPORT_COMPLIANCE" {
                        print("::warning::The build needs an export compliance answer in App Store Connect")
                    }
                    exit(0)
                case "FAILED", "INVALID":
                    print("::error::App Store Connect marked build \(version) (\(buildNumber)) \(state). The reason is in the email from App Store Connect.")
                    exit(1)
                default:
                    try await Task.sleep(nanoseconds: pollSeconds * 1_000_000_000)
                }
            }
            print("::warning::Build \(version) (\(buildNumber)) is still \(lastState) after \(Int(timeLimit / 60)) minutes. It was uploaded and should appear in TestFlight soon.")
            exit(0)
        } catch {
            print("::error::\(error)")
            exit(1)
        }
    }

    static func environment(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw APIError(description: "\(name) is not set")
        }
        return value
    }
}
