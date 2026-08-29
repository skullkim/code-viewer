/// A 24-bit colour from Neovim's highlight attributes.
public struct EditorColor: Sendable, Hashable, Codable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Builds a colour from Neovim's packed `0xRRGGBB` integer.
    public init(packedRGB: Int) {
        self.red = UInt8((packedRGB >> 16) & 0xFF)
        self.green = UInt8((packedRGB >> 8) & 0xFF)
        self.blue = UInt8(packedRGB & 0xFF)
    }
}
