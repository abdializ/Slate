import Foundation

/// Length-prefixed native messaging. A separate queue owns the parser and all
/// writes. No shell, disk transcript, or helper stderr is used.
final class HostPipe {
    var onMessage: ((Any) -> Void)?
    var onExit: (() -> Void)?
    private let program: URL
    private let origin: String
    private let queue = DispatchQueue(label: "dev.slate.password-helper")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var bytes = Data()
    private var ended = false
    static let limit = 1024 * 1024
    init(program: URL, origin: String) { self.program = program; self.origin = origin }
    func start() throws {
        // Only the immutable system helper, validated again immediately before launch.
        guard AppleHelper.program() == program else { throw ApplePasswordsError.gone }
        let task = Process(), toHelper = Pipe(), fromHelper = Pipe()
        task.executableURL = program
        task.arguments = [origin]
        task.standardInput = toHelper
        task.standardOutput = fromHelper
        task.standardError = FileHandle.nullDevice
        process = task; input = toHelper.fileHandleForWriting; output = fromHelper.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async { [weak self] in self?.receive(data) }
        }
        task.terminationHandler = { [weak self] _ in self?.queue.async { [weak self] in self?.finish() } }
        do { try task.run() } catch { stop(); throw error }
    }
    func write(_ value: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        guard data.count <= Self.limit else { throw ApplePasswordsError.malformed("message too large") }
        try queue.sync {
            guard !ended, let input else { throw ApplePasswordsError.gone }
            var size = UInt32(data.count).littleEndian
            var packet = withUnsafeBytes(of: &size) { Data($0) }
            packet.append(data)
            try input.write(contentsOf: packet)
        }
    }
    private func receive(_ data: Data) {
        guard !ended else { return }
        guard !data.isEmpty else { finish(); return }
        bytes.append(data)
        while bytes.count >= 4 {
            let count = bytes.prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
            guard count > 0, count <= Self.limit else { finish(); return }
            guard bytes.count >= 4 + Int(count) else { return }
            let frame = bytes.subdata(in: 4..<(4 + Int(count)))
            bytes = Data(bytes.dropFirst(4 + Int(count)))
            guard let value = try? JSONSerialization.jsonObject(with: frame) else { finish(); return }
            onMessage?(value)
        }
    }
    private func finish() {
        guard !ended else { return }
        ended = true
        output?.readabilityHandler = nil
        try? input?.close(); try? output?.close()
        input = nil; output = nil; bytes.removeAll()
        if process?.isRunning == true { process?.terminate() }
        process = nil
        onExit?()
    }
    func stop() { queue.sync { finish() } }
    deinit { output?.readabilityHandler = nil; if process?.isRunning == true { process?.terminate() } }
}
