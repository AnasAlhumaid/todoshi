import Foundation

public struct AppleIdentityTokenClaimReport: Sendable, Equatable {
    public let identityTokenPresent: Bool
    public let issuerIsApple: Bool
    public let audienceMatchesExpected: Bool
    public let nonceClaimPresent: Bool

    public init(
        identityTokenPresent: Bool,
        issuerIsApple: Bool,
        audienceMatchesExpected: Bool,
        nonceClaimPresent: Bool
    ) {
        self.identityTokenPresent = identityTokenPresent
        self.issuerIsApple = issuerIsApple
        self.audienceMatchesExpected = audienceMatchesExpected
        self.nonceClaimPresent = nonceClaimPresent
    }
}

public enum AppleIdentityTokenDiagnostics: Sendable {
    public static let expectedNativeAudience = "com.anashamad.Todoshi"
    private static let appleIssuer = "https://appleid.apple.com"

    /// Inspects JWT payload claims without logging token contents or claim values.
    public static func report(for identityToken: String?) -> AppleIdentityTokenClaimReport {
        guard let identityToken, !identityToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AppleIdentityTokenClaimReport(
                identityTokenPresent: false,
                issuerIsApple: false,
                audienceMatchesExpected: false,
                nonceClaimPresent: false
            )
        }

        guard let payload = jwtPayload(from: identityToken) else {
            return AppleIdentityTokenClaimReport(
                identityTokenPresent: true,
                issuerIsApple: false,
                audienceMatchesExpected: false,
                nonceClaimPresent: false
            )
        }

        let issuer = payload["iss"] as? String
        let audience = payload["aud"] as? String
        let nonce = payload["nonce"] as? String

        return AppleIdentityTokenClaimReport(
            identityTokenPresent: true,
            issuerIsApple: issuer == appleIssuer,
            audienceMatchesExpected: audience == expectedNativeAudience,
            nonceClaimPresent: nonce.map { !$0.isEmpty } ?? false
        )
    }

    static func jwtPayload(from token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

public enum AuthRuntimeIdentityAudit: Sendable {
    public static let expectedBundleIdentifier = "com.anashamad.Todoshi"

    public struct Report: Sendable, Equatable {
        public let bundleIdentifier: String?
        public let bundleIdentifierMatchesExpected: Bool

        public init(bundleIdentifier: String?) {
            self.bundleIdentifier = bundleIdentifier
            self.bundleIdentifierMatchesExpected = bundleIdentifier == expectedBundleIdentifier
        }
    }

    public static func report(bundleIdentifier: String?) -> Report {
        Report(bundleIdentifier: bundleIdentifier)
    }
}
