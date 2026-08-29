/// What happened to a file, reduced to what the index actually needs to know.
///
/// FSEvents reports flags that are OR'd together and often repeated for the same path in one
/// batch, so trying to reconstruct exactly what happened is unreliable. Only one distinction
/// matters: does this path still exist and need re-reading, or is it gone?
enum FileChangeKind: Equatable {
    case changed
    case removed
}
