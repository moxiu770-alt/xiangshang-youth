import SwiftUI

enum AppTheme {
    static let primary = Color(hex: "1769E0")
    static let teal = Color(hex: "12A594")
    static let ink = Color(hex: "16233B")
    static let muted = Color(hex: "65758B")
    static let surface = Color(hex: "F5F8FC")
    static let surfaceRaised = Color.white
    static let divider = Color(hex: "DCE5F0")
    static let danger = Color(hex: "E35D5B")
    static let warning = Color(hex: "E58A16")

    static let pagePadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 24
    static let cardSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 18
    static let controlHeight: CGFloat = 54
    static let minimumTapSize: CGFloat = 48
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 12

    // The product is used by parents and teachers in busy real-world
    // environments. Keep the default reading size one step above the iOS
    // compact baseline; Dynamic Type can continue scaling from here.
    static let displaySize: CGFloat = 32
    static let pageTitleSize: CGFloat = 24
    static let sectionTitleSize: CGFloat = 20
    static let bodySize: CGFloat = 17
    static let secondarySize: CGFloat = 15
    static let captionSize: CGFloat = 14
    static let buttonSize: CGFloat = 17
}
