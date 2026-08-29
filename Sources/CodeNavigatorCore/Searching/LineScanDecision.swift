/// Whether a line scan should keep going after the current line.
///
/// A caller that has filled its result cap says so explicitly, instead of the scanner guessing
/// from a returned `Bool` what `true` was supposed to mean.
enum LineScanDecision {
    case continueScanning
    case stopScanning
}
