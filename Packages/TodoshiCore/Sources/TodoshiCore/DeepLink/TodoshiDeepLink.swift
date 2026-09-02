import Foundation

/// Typed deep links for navigation and widget handoff.
public enum NexusDeepLink: Equatable, Sendable {
    public static let scheme = "nexus"
    public static let baseProjectIDQueryItem = "baseProjectID"

    case quickAdd
    case task(UUID)
    case project(UUID)
    case dashboard
    case projects
    /// Live Project Tasks widget project override picker (`nexus://widget/project-picker?baseProjectID=`).
    case widgetProjectPicker(baseProjectID: UUID?)

    public var url: URL {
        switch self {
        case .quickAdd:
            return URL(string: "\(Self.scheme)://quick-add")!
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
        }
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }

        let host = url.host?.lowercased() ?? ""
        let pathParts = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "quick-add":
            self = .quickAdd
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
                    self = .quickAdd
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
