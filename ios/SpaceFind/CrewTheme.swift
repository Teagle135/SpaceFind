import SwiftUI
import UIKit

enum CrewTheme {
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemBackground : UIColor(red: 249 / 255, green: 251 / 255, blue: 249 / 255, alpha: 1)
    })

    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .label
            : UIColor(red: 27 / 255, green: 41 / 255, blue: 40 / 255, alpha: 1)
    })

    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 125 / 255, green: 201 / 255, blue: 174 / 255, alpha: 1)
            : UIColor(red: 32 / 255, green: 94 / 255, blue: 80 / 255, alpha: 1)
    })

    static let divider = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .separator
            : UIColor(red: 220 / 255, green: 227 / 255, blue: 221 / 255, alpha: 1)
    })
}

struct CrewWordmark: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("//")
                .font(.system(size: 10, weight: .bold))
                .accessibilityHidden(true)
            Text("SPACEFIND")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
        }
        .foregroundStyle(CrewTheme.accent)
    }
}
