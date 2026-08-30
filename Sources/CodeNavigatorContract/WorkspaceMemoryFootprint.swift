import Foundation

/// What the workspace is costing, for REQ-NF-002 and the AC-3 check.
///
/// ⚠ **AC-3 must not be judged by this number going down.** Closing a tab releases the index, but
/// the allocator keeps the pages and hands them back to the next project rather than returning
/// them to the system — measured: reopening after a close costs about 0.4MB, not another full
/// index. So a close that frees nothing visible is normal, and the question worth asking is
/// whether repeated open/close **grows** the footprint. Reading a flat number as a leak would
/// condemn correct behaviour; expecting a drop would fail a correct implementation.
public struct WorkspaceMemoryFootprint: Sendable, Hashable {
    /// The process footprint, the same number Instruments and the memory gauge report.
    public let processFootprintBytes: Int

    public let openTabCount: Int

    /// Symbols held across every open tab — the part that actually scales with projects.
    public let indexedSymbolCount: Int

    public init(processFootprintBytes: Int, openTabCount: Int, indexedSymbolCount: Int) {
        self.processFootprintBytes = processFootprintBytes
        self.openTabCount = openTabCount
        self.indexedSymbolCount = indexedSymbolCount
    }
}
