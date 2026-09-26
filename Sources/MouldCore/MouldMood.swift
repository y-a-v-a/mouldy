/// What the menu bar says about the state of your screen.
public enum MouldMood {
    public static let lines: [(upTo: Double, text: String)] = [
        (0.0, "Fresh as a daisy"),
        (0.12, "Something's landed…"),
        (0.25, "Is that… fuzz?"),
        (0.45, "Definitely mould. Take a break?"),
        (0.65, "Ieuw. Seriously, stand up."),
        (0.85, "Your screen is a science project"),
        (1.0, "Fully furry. Go outside."),
    ]

    public static func headline(progress: Double) -> String {
        let p = min(1, max(0, progress))
        return lines.first { p <= $0.upTo }?.text ?? lines[lines.count - 1].text
    }
}
