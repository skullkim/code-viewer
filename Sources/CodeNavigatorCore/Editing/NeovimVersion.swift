/// A Neovim version, for the minimum-version check (REQ-NF-005).
///
/// Only the three numeric components are compared. Pre-release suffixes such as `-dev` are
/// ignored rather than rejected: a developer running a nightly build should not be told their
/// editor is unusable when its version number is in fact new enough.
struct NeovimVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    /// The oldest Neovim whose API this engine relies on.
    static let minimumSupported = NeovimVersion(major: 0, minor: 9, patch: 0)

    var description: String { "\(major).\(minor).\(patch)" }

    /// Parses the first `x.y.z` found in `nvim --version` output, which starts with
    /// `NVIM v0.12.5`. Returns `nil` when no version number is present at all.
    init?(versionOutput: String) {
        var digits: [Int] = []
        var current = ""
        var started = false

        for character in versionOutput {
            if character.isNumber {
                current.append(character)
                started = true
                continue
            }
            if character == "." , started, !current.isEmpty {
                digits.append(Int(current) ?? 0)
                current = ""
                if digits.count == 3 { break }
                continue
            }
            if started, !current.isEmpty {
                digits.append(Int(current) ?? 0)
                break
            }
            current = ""
            started = false
        }
        if !current.isEmpty, digits.count < 3 {
            digits.append(Int(current) ?? 0)
        }
        guard digits.count >= 2 else { return nil }

        self.major = digits[0]
        self.minor = digits[1]
        self.patch = digits.count > 2 ? digits[2] : 0
    }

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (left: NeovimVersion, right: NeovimVersion) -> Bool {
        (left.major, left.minor, left.patch) < (right.major, right.minor, right.patch)
    }
}
