import UIKit
import TodoshiCore

@MainActor
enum PresentingViewControllerResolver {
    struct Resolution {
        let viewController: UIViewController
        let foundActiveScene: Bool
        let foundKeyWindow: Bool
    }

    static func topViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        resolve(base: base)?.viewController
    }

    /// Resolves a presenter from the foreground active scene when possible.
    static func resolve(base: UIViewController? = nil) -> Resolution? {
        if let base {
            let top = topmost(from: base)
            #if DEBUG
            TodoshiDiagnostics.note(
                "[AccountDeletion][Google] presenter found=true activeScene=n/a keyWindow=n/a (explicit base)"
            )
            #endif
            return Resolution(viewController: top, foundActiveScene: true, foundKeyWindow: top.view.window != nil)
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        let foundActiveScene = activeScene != nil

        let windows = (activeScene?.windows ?? scenes.flatMap(\.windows))
        let keyWindow = windows.first(where: \.isKeyWindow) ?? windows.first
        let foundKeyWindow = keyWindow != nil

        guard let root = keyWindow?.rootViewController else {
            #if DEBUG
            TodoshiDiagnostics.note(
                "[AccountDeletion][Google] presenter found=false activeScene=\(foundActiveScene) keyWindow=\(foundKeyWindow)"
            )
            #endif
            return nil
        }

        let top = topmost(from: root)
        let attached = top.viewIfLoaded?.window != nil
        #if DEBUG
        TodoshiDiagnostics.note(
            "[AccountDeletion][Google] presenter found=\(attached) activeScene=\(foundActiveScene) keyWindow=\(foundKeyWindow)"
        )
        #endif
        guard attached else { return nil }
        return Resolution(
            viewController: top,
            foundActiveScene: foundActiveScene,
            foundKeyWindow: foundKeyWindow
        )
    }

    private static func topmost(from root: UIViewController) -> UIViewController {
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
            return topmost(from: visible)
        }
        if let tab = top as? UITabBarController, let selected = tab.selectedViewController {
            return topmost(from: selected)
        }
        return top
    }
}
