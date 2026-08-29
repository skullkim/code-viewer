/// The result of one full scan: every visible file, and which of them can be indexed.
///
/// Both lists are project-root-relative POSIX paths, sorted, so repeated scans are comparable
/// and no caller can accidentally depend on filesystem enumeration order.
struct ProjectScan {
    let filePaths: [String]
    let indexableFilePaths: [String]

    var fileSet: Set<String> { Set(filePaths) }
}
