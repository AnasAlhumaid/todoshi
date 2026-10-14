import Foundation

/// Permanent, user-facing Todoshi account identifier (`TD-XXXX-XXXX-XXXXX`).
public enum TodoshiIDPolicy: Sendable {
    public static let prefix = "TD-"
    public static let payloadCharacterCount = 13
    public static let randomByteCount = 8

    /// Crockford Base32 without I, L, O, U.
    public static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static let formatPattern =
        #"^TD-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{5}$"#

    public static func isValid(_ id: String) -> Bool {
        id.range(of: formatPattern, options: .regularExpression) != nil
    }

    public static func hasValidPrefix(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    public static func usesAllowedAlphabet(_ id: String) -> Bool {
        let payload = id
            .replacingOccurrences(of: prefix, with: "")
            .replacingOccurrences(of: "-", with: "")
        guard payload.count == payloadCharacterCount else { return false }
        let allowed = Set(alphabet)
        return payload.allSatisfy { allowed.contains($0) }
    }

    /// Encodes secure random bytes into a grouped Todoshi ID.
    public static func generate(randomBytes: [UInt8]) -> String {
        precondition(randomBytes.count >= randomByteCount)
        let payload = encodeCrockfordBase32(bytes: randomBytes, characterCount: payloadCharacterCount)
        return formatted(fromPayload: payload)
    }

    public static func formatted(fromPayload payload: String) -> String {
        precondition(payload.count == payloadCharacterCount)
        let start = payload.startIndex
        let g1End = payload.index(start, offsetBy: 4)
        let g2End = payload.index(start, offsetBy: 8)
        let g3End = payload.index(start, offsetBy: 13)
        let g1 = payload[start..<g1End]
        let g2 = payload[g1End..<g2End]
        let g3 = payload[g2End..<g3End]
        return "\(prefix)\(g1)-\(g2)-\(g3)"
    }

    /// VoiceOver-friendly reading with spaces between characters.
    public static func accessibilitySpoken(_ id: String) -> String {
        id.map { String($0) }.joined(separator: " ")
    }

    private static func encodeCrockfordBase32(bytes: [UInt8], characterCount: Int) -> String {
        var bits = 0
        var bitCount = 0
        var output = ""
        for byte in bytes {
            bits = (bits << 8) | Int(byte)
            bitCount += 8
            while bitCount >= 5, output.count < characterCount {
                bitCount -= 5
                let index = (bits >> bitCount) & 0x1F
                output.append(alphabet[index])
            }
        }
        if output.count < characterCount, bitCount > 0 {
            let index = (bits << (5 - bitCount)) & 0x1F
            output.append(alphabet[index])
        }
        return String(output.prefix(characterCount))
    }
}
