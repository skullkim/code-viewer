/// Why decoding stopped.
///
/// The two cases mean opposite things to the caller, which is the point: a pipe hands over
/// bytes that stop anywhere, not on frame boundaries, so "wait for more" must be
/// distinguishable from "this stream is corrupt".
public enum MessagePackError: Error, Equatable {
    /// The buffer ends inside a frame. Read more bytes, append them, and decode again.
    case needsMoreBytes

    /// A byte that MessagePack never emits. Retrying cannot help.
    case unsupportedFormatByte(UInt8)
}
