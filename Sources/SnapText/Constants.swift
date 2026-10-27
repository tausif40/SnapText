import Foundation

/// The people, links and addresses SnapText shows or opens, kept in one place.
enum Constants {
    static let developerName = "Mohd Tausif"
    static let developerEmail = "tausif6040@gmail.com"
    static let portfolio = URL(string: "https://tausif.info")!

    /// Where people can chip in towards the app's upkeep.
    static let supportPage = URL(string: "https://tausif.info/OCRpay")!

    /// The Screen Recording list in System Settings.
    static let screenRecordingSettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    /// The Accessibility list in System Settings.
    static let accessibilitySettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}
