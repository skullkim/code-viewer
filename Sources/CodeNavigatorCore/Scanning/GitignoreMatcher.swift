/// Decides whether a path is ignored, given the `.gitignore` files that govern it.
///
/// Two ordering rules decide conflicts, both taken from git:
/// - a deeper `.gitignore` overrides a shallower one,
/// - within one file, the last matching line wins.
///
/// Re-including a file inside an ignored directory is intentionally not supported, matching git.
/// The scanner never descends into an ignored directory, so the case cannot arise.
struct GitignoreMatcher {
    private let ruleSets: [GitignoreRuleSet]

    init(ruleSets: [GitignoreRuleSet]) {
        // Shallowest first, so iterating forward lets deeper files overwrite the verdict.
        self.ruleSets = ruleSets.sorted { $0.depth < $1.depth }
    }

    func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        var verdict = false
        for ruleSet in ruleSets {
            guard let localPath = ruleSet.pathRelativeToBase(relativePath), !localPath.isEmpty else {
                continue
            }
            for pattern in ruleSet.patterns
            where pattern.matches(relativePath: localPath, isDirectory: isDirectory) {
                verdict = !pattern.isNegated
            }
        }
        return verdict
    }

    var isEmpty: Bool {
        ruleSets.allSatisfy { $0.patterns.isEmpty }
    }
}
