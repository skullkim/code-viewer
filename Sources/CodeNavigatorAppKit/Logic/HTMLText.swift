import Foundation

/// Turning author text into HTML that says the same thing.
///
/// One implementation, deliberately. Escaping lived inside the markdown converter until the
/// blocked-resource box needed it too, and two copies of an escaping rule is the shape of a
/// bug that only shows up on one of the two paths — which is the path nobody tested.
public enum HTMLText {

    /// `&` first. Any other order turns `<` into `&amp;lt;`, which the reader sees literally.
    public static func escaped(_ text: String) -> String {
        var output = ""
        for character in text {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            default: output.append(character)
            }
        }
        return output
    }

    /// Everything `escaped` does, plus the quote — an unescaped quote ends the attribute it
    /// sits in and turns the rest of the author's text into attributes of ours.
    public static func escapedAttribute(_ text: String) -> String {
        escaped(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
