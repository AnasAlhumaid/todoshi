import Foundation

/// Typed deep links for navigation and widget handoff.
public enum TodoshiDeepLink: Equatable, Sendable {
    public static let scheme = "todoshi"
    /// Legacy compatibility parser only — new URLs must use `scheme`.
    public static let legacyScheme = "nexus"
    public static let baseProjectIDQueryItem = "baseProjectID"
    public static let projectIDQueryItem = "projectID"

    case quickAdd(projectID: UUID? = nil)
    case task(UUID)
    case project(UUID)
    case dashboard
    case projects
    /// Live Project Tasks widget project override picker (`todoshi://widget/project-picker?baseProjectID=`).
    case widgetProjectPicker(baseProjectID: UUID?)
    /// Capability invite (`todoshi://invite/<token>`).
    case invite(token: String)

    public var url: URL {
        switch self {
        case .quickAdd(let projectID):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "quick-add"
            if let projectID {
                components.queryItems = [
                    URLQueryItem(name: Self.projectIDQueryItem, value: projectID.uuidString)
                ]
            }
            return components.url!
        case .task(let id):
            return URL(string: "\(Self.scheme)://task/\(id.uuidString)")!
        case .project(let id):
            return URL(string: "\(Self.scheme)://project/\(id.uuidString)")!
        case .dashboard:
            return URL(string: "\(Self.scheme)://dashboard")!
        case .projects:
            return URL(string: "\(Self.scheme)://projects")!
        case .widgetProjectPicker(let baseID):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "widget"
            components.path = "/project-picker"
            if let baseID {
                components.queryItems = [
                    URLQueryItem(name: Self.baseProjectIDQueryItem, value: baseID.uuidString)
                ]
            }
            return components.url!
        case .invite(let token):
            return ProjectInviteURLBuilder.url(token: token)!
        }
    }

    public init?(url: URL) {
        guard let parsedScheme = url.scheme?.lowercased(),
              parsedScheme == Self.scheme || parsedScheme == Self.legacyScheme else {
            return nil
        }

        let host = url.host?.lowercased() ?? ""
        let pathParts = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "quick-add":
            let projectID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == Self.projectIDQueryItem })?
                .value
                .flatMap(UUID.init(uuidString:))
            self = .quickAdd(projectID: projectID)
        case "task":
            guard let raw = pathParts.first, let id = UUID(uuidString: raw) else { return nil }
            self = .task(id)
        case "project":
            guard let raw = pathParts.first, let id = UUID(uuidString: raw) else { return nil }
            self = .project(id)
        case "dashboard":
            self = .dashboard
        case "projects":
            self = .projects
        case "invite":
            // Invite deep links are Todoshi-only (not legacy nexus).
            guard parsedScheme == Self.scheme else { return nil }
            guard let token = pathParts.first,
                  ProjectInviteTokenGenerator.isValidFormat(token) else {
                return nil
            }
            self = .invite(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        case "widget":
            guard let segment = pathParts.first?.lowercased(), segment == "project-picker" else {
                return nil
            }
            let queryID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == Self.baseProjectIDQueryItem })?
                .value
            let base = queryID.flatMap(UUID.init(uuidString:))
            self = .widgetProjectPicker(baseProjectID: base)
        default:
            if host.isEmpty, let first = pathParts.first?.lowercased() {
                switch first {
                case "quick-add":
                    let projectID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == Self.projectIDQueryItem })?
                        .value
                        .flatMap(UUID.init(uuidString:))
                    self = .quickAdd(projectID: projectID)
                case "dashboard":
                    self = .dashboard
                case "projects":
                    self = .projects
                default:
                    return nil
                }
                return
            }
            return nil
        }
    }
}
