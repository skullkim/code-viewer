import Foundation

/// Turns a pipe's arbitrary byte chunks into an ordered stream of decoded MessagePack values.
///
/// Ordering is the whole point. A pipe stops wherever the kernel stopped, so frames arrive split
/// and glued together, and any scheme that hands chunks off to concurrent tasks can reorder them
/// and corrupt the stream. Buffering happens here, behind a lock, and complete frames are yielded
/// to a single `AsyncStream` whose delivery order is guaranteed.
final class NeovimByteStream: @unchecked Sendable {
    /// A value decoded from the channel, or the failure that ended the stream.
    enum Event {
        case value(MessagePackValue)
        case corrupted(UInt8)
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let lock = NSLock()
    private var buffer: [UInt8] = []
    private var hasFailed = false

    init() {
        var capturedContinuation: AsyncStream<Event>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation
    }

    /// Appends a chunk and yields every frame that is now complete.
    func append(_ chunk: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasFailed else { return }

        buffer.append(contentsOf: chunk)

        var decoder = MessagePackDecoder(bytes: buffer)
        var consumed = 0
        while consumed < buffer.count {
            do {
                let value = try decoder.decodeValue()
                consumed = decoder.position
                continuation.yield(.value(value))
            } catch MessagePackError.needsMoreBytes {
                // A partial frame is normal — keep it and wait for the next read.
                break
            } catch MessagePackError.unsupportedFormatByte(let byte) {
                // Corruption cannot be recovered from by waiting; resyncing would only invent
                // plausible-looking garbage. End the stream and let the session report it.
                hasFailed = true
                continuation.yield(.corrupted(byte))
                continuation.finish()
                return
            } catch {
                break
            }
        }

        if consumed > 0 {
            buffer.removeFirst(consumed)
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        continuation.finish()
    }
}
