/// The resolved appearance of a run of editor text.
///
/// `nil` foreground or background means "use the grid default", which the snapshot carries.
public struct EditorTextStyle: Sendable, Hashable, Codable {
    public let foreground: EditorColor?
    public let background: EditorColor?
    public let isBold: Bool
    public let isItalic: Bool
    public let isUnderlined: Bool
    public let isReverseVideo: Bool

    public static let plain = EditorTextStyle()

    public init(
        foreground: EditorColor? = nil,
        background: EditorColor? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        isReverseVideo: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isReverseVideo = isReverseVideo
    }
}
