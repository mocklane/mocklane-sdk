import Foundation
#if os(iOS) && !targetEnvironment(simulator)
import UIKit
#endif

/// USB mux + local reverse proxy for physical iOS devices (Flipper-style).
///
/// Desktop opens a usbmux tunnel to mux port 26625. The SDK listens with POSIX
/// IPv4 sockets (usbmux-compatible), then relays `127.0.0.1:<gatewayPort>` over
/// that tunnel. No Mac LAN IP required.
///
/// After screen lock, iOS may suspend the process and stop delivering GCD accept
/// events. On foreground/active the bridge re-binds listen sockets so Desktop
/// auto-reconnect can succeed without relaunching the app. No UIBackgroundModes
/// required — traffic during lock is still limited by OS suspension.
///
/// Simulator must not enable this — `127.0.0.1:6625` is already the Mac gateway.
enum UsbBridge {
    static let defaultMuxPort: UInt16 = 26625

    private static let magic = Data([0x4D, 0x4C, 0x55, 0x53]) // MLUS
    private static let version: UInt8 = 1

    private static let msgHello: UInt8 = 1
    private static let msgHelloAck: UInt8 = 2
    private static let msgOpen: UInt8 = 3
    private static let msgOpenAck: UInt8 = 4
    private static let msgOpenFail: UInt8 = 5
    private static let msgData: UInt8 = 6
    private static let msgClose: UInt8 = 7

    private static let lock = NSLock()
    #if os(iOS) && !targetEnvironment(simulator)
    private static var runtime: Runtime?
    #endif

    /// Start on physical iOS when host is loopback. No-op on Simulator / macOS.
    static func startIfNeeded(config: MocklaneConfig) {
        #if os(iOS) && !targetEnvironment(simulator)
        let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard host == "127.0.0.1" || host == "localhost" else { return }
        let gatewayPort = UInt16(clamping: config.port)
        lock.lock()
        runtime?.stop()
        let rt = Runtime(gatewayPort: gatewayPort, muxPort: defaultMuxPort)
        runtime = rt
        lock.unlock()
        rt.start()
        #else
        _ = config
        #endif
    }

    static func stop() {
        #if os(iOS) && !targetEnvironment(simulator)
        lock.lock()
        runtime?.stop()
        runtime = nil
        lock.unlock()
        #endif
    }

    /// Re-bind USB listen sockets after unlock/foreground. No-op if bridge inactive.
    static func ensureListening() {
        #if os(iOS) && !targetEnvironment(simulator)
        lock.lock()
        let rt = runtime
        lock.unlock()
        rt?.ensureListening()
        #endif
    }

    #if os(iOS) && !targetEnvironment(simulator)
    private final class Runtime: @unchecked Sendable {
        let gatewayPort: UInt16
        let muxPort: UInt16
        private let queue = DispatchQueue(label: "io.mocklane.usb-bridge")
        private var muxListenFd: Int32 = -1
        private var localListenFd: Int32 = -1
        private var muxListenSource: DispatchSourceRead?
        private var localListenSource: DispatchSourceRead?
        private var muxFd: Int32 = -1
        private var muxReadSource: DispatchSourceRead?
        private var nextStreamId: UInt32 = 1
        private var localSockets: [UInt32: LocalSocket] = [:]
        private var pendingLocal: [UInt32: LocalSocket] = [:]
        /// Local accepts while mux is down — hold briefly for Desktop reconnect.
        private var waitingLocal: [(fd: Int32, deadline: DispatchTime)] = []
        private var waitTimer: DispatchSourceTimer?
        private var healTimer: DispatchSourceTimer?
        private var readBuffer = Data()
        private var sawMagic = false
        private var lifecycleObservers: [NSObjectProtocol] = []
        private var ensureScheduled = false

        /// How long a device→localhost request waits for Desktop mux to return.
        /// Keep ≤ typical `probeTimeoutMs` so health probe can succeed after reconnect.
        private static let muxWaitNanoseconds: UInt64 = 2_500_000_000
        private static let waitTickMs: Int = 100
        private static let healIntervalMs: Int = 1_000
        private static let bindRetryCount: Int = 8
        private static let bindRetryDelayUs: useconds_t = 25_000

        init(gatewayPort: UInt16, muxPort: UInt16) {
            self.gatewayPort = gatewayPort
            self.muxPort = muxPort
        }

        func start() {
            registerLifecycleObservers()
            queue.async { [weak self] in
                guard let self else { return }
                self.rebindListen(kind: .mux)
                self.rebindListen(kind: .local)
                self.armHealTimer()
            }
        }

        func stop() {
            unregisterLifecycleObservers()
            queue.async { [weak self] in
                guard let self else { return }
                self.waitTimer?.cancel()
                self.waitTimer = nil
                self.healTimer?.cancel()
                self.healTimer = nil
                for (fd, _) in self.waitingLocal { Darwin.close(fd) }
                self.waitingLocal.removeAll()
                self.closeListen(kind: .mux)
                self.closeListen(kind: .local)
                self.dropMuxSession()
            }
        }

        /// Re-bind mux + local listen after unlock/foreground. Debounced; safe often.
        func ensureListening() {
            queue.async { [weak self] in
                guard let self else { return }
                // Coalesce willEnterForeground + didBecomeActive + protectedData.
                if self.ensureScheduled { return }
                self.ensureScheduled = true
                self.queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
                    guard let self else { return }
                    self.ensureScheduled = false
                    self.rebindListen(kind: .mux)
                    self.rebindListen(kind: .local)
                }
            }
        }

        private func registerLifecycleObservers() {
            unregisterLifecycleObservers()
            let center = NotificationCenter.default
            var names: [Notification.Name] = [
                UIApplication.willEnterForegroundNotification,
                UIApplication.didBecomeActiveNotification,
            ]
            names.append(UIApplication.protectedDataDidBecomeAvailableNotification)
            for name in names {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.ensureListening()
                }
                lifecycleObservers.append(token)
            }
        }

        private func unregisterLifecycleObservers() {
            let center = NotificationCenter.default
            for token in lifecycleObservers {
                center.removeObserver(token)
            }
            lifecycleObservers.removeAll()
        }

        private enum Kind { case mux, local }

        /// Close listen fd synchronously. Avoid async cancel-handler close → bind
        /// EADDRINUSE race that leaves *no* listener until the next lifecycle event.
        private func closeListen(kind: Kind) {
            switch kind {
            case .mux:
                if let src = muxListenSource {
                    src.setEventHandler {}
                    src.setCancelHandler {}
                    muxListenSource = nil
                    src.cancel()
                }
                if muxListenFd >= 0 {
                    Darwin.close(muxListenFd)
                    muxListenFd = -1
                }
            case .local:
                if let src = localListenSource {
                    src.setEventHandler {}
                    src.setCancelHandler {}
                    localListenSource = nil
                    src.cancel()
                }
                if localListenFd >= 0 {
                    Darwin.close(localListenFd)
                    localListenFd = -1
                }
            }
        }

        private func rebindListen(kind: Kind) {
            closeListen(kind: kind)
            let port = kind == .mux ? muxPort : gatewayPort
            for attempt in 0..<Self.bindRetryCount {
                if listen(port: port, kind: kind) { return }
                if attempt + 1 < Self.bindRetryCount {
                    usleep(Self.bindRetryDelayUs)
                }
            }
            NSLog(
                "Mocklane UsbBridge: failed to bind listen port %u (%@) after %d tries",
                port,
                kind == .mux ? "mux" : "local",
                Self.bindRetryCount
            )
        }

        private func fdLooksOpen(_ fd: Int32) -> Bool {
            fd >= 0 && fcntl(fd, F_GETFD) != -1
        }

        private func armHealTimer() {
            guard healTimer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(
                deadline: .now() + .milliseconds(Self.healIntervalMs),
                repeating: .milliseconds(Self.healIntervalMs)
            )
            t.setEventHandler { [weak self] in self?.healIfNeeded() }
            t.resume()
            healTimer = t
        }

        /// Self-heal when a prior rebind raced and left no listener (common after lock).
        private func healIfNeeded() {
            let muxOk = fdLooksOpen(muxListenFd) && muxListenSource != nil
            let localOk = fdLooksOpen(localListenFd) && localListenSource != nil
            if !muxOk { rebindListen(kind: .mux) }
            if !localOk { rebindListen(kind: .local) }
        }

        @discardableResult
        private func listen(port: UInt16, kind: Kind) -> Bool {
            let fd = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard fd >= 0 else { return false }
            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            // usbmuxd connects over loopback; the bridge must never be
            // reachable from the local network.
            addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK)
            let bindOk: Bool = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
            guard bindOk, Darwin.listen(fd, 16) == 0 else {
                Darwin.close(fd)
                return false
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in
                self?.onAccept(listenFd: fd, kind: kind)
            }
            // Fd closed by closeListen (sync) — cancel handler must not close again.
            source.setCancelHandler {}
            source.resume()
            switch kind {
            case .mux:
                muxListenFd = fd
                muxListenSource = source
            case .local:
                localListenFd = fd
                localListenSource = source
            }
            return true
        }

        private func onAccept(listenFd: Int32, kind: Kind) {
            var addr = sockaddr_storage()
            var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let client: Int32 = withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(listenFd, $0, &len)
                }
            }
            guard client >= 0 else { return }
            switch kind {
            case .mux: attachMux(client)
            case .local: attachLocal(client)
            }
        }

        private func attachMux(_ fd: Int32) {
            muxReadSource?.cancel()
            if muxFd >= 0 { Darwin.close(muxFd) }
            muxFd = fd
            readBuffer.removeAll()
            sawMagic = false
            var nodelay: Int32 = 1
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, socklen_t(MemoryLayout.size(ofValue: nodelay)))
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.readMux() }
            src.resume()
            muxReadSource = src
            // Do not flush waitingLocal here — Desktop must finish HELLO first.
            // flushWaitingLocal runs after HELLO_ACK in onFrame.
        }

        private func attachLocal(_ fd: Int32) {
            if muxFd >= 0 {
                openLocalStream(fd)
                return
            }
            // Tunnel briefly down (cable / lock / Desktop reconnect). Hold the
            // localhost accept so probe+Fetch can succeed once mux returns.
            let deadline = DispatchTime.now() + .milliseconds(Int(Self.muxWaitNanoseconds / 1_000_000))
            waitingLocal.append((fd, deadline))
            armWaitTimer()
        }

        private func openLocalStream(_ fd: Int32) {
            let streamId = nextStreamId
            nextStreamId &+= 1
            let local = LocalSocket(fd: fd, queue: queue)
            pendingLocal[streamId] = local
            var payload = Data()
            payload.append(contentsOf: gatewayPort.bigEndianBytes)
            sendFrame(UsbBridge.msgOpen, streamId: streamId, payload: payload)
        }

        private func flushWaitingLocal() {
            guard muxFd >= 0, !waitingLocal.isEmpty else { return }
            let pending = waitingLocal
            waitingLocal.removeAll()
            waitTimer?.cancel()
            waitTimer = nil
            for (fd, _) in pending {
                openLocalStream(fd)
            }
        }

        private func armWaitTimer() {
            guard waitTimer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(
                deadline: .now() + .milliseconds(Self.waitTickMs),
                repeating: .milliseconds(Self.waitTickMs)
            )
            t.setEventHandler { [weak self] in self?.tickWaitingLocal() }
            t.resume()
            waitTimer = t
        }

        private func tickWaitingLocal() {
            if muxFd >= 0 {
                flushWaitingLocal()
                return
            }
            let now = DispatchTime.now()
            var keep: [(fd: Int32, deadline: DispatchTime)] = []
            for item in waitingLocal {
                if item.deadline > now {
                    keep.append(item)
                } else {
                    Darwin.close(item.fd)
                }
            }
            waitingLocal = keep
            if waitingLocal.isEmpty {
                waitTimer?.cancel()
                waitTimer = nil
            }
        }

        private func readMux() {
            var buf = [UInt8](repeating: 0, count: 64 * 1024)
            let n = Darwin.read(muxFd, &buf, buf.count)
            if n <= 0 {
                dropMux()
                return
            }
            readBuffer.append(contentsOf: buf[0..<n])
            pumpFrames()
        }

        private func dropMux() {
            // Session only — keep mux/local *listen* sockets so Desktop
            // auto-reconnect (and post-unlock ensureListening) can accept again
            // without relaunching the app.
            dropMuxSession()
        }

        private func dropMuxSession() {
            muxReadSource?.cancel()
            muxReadSource = nil
            if muxFd >= 0 {
                Darwin.close(muxFd)
                muxFd = -1
            }
            // Drop in-flight streams; keep waitingLocal so a quick Desktop
            // reconnect can still serve the next probe/Fetch.
            for (_, s) in localSockets { s.close() }
            for (_, s) in pendingLocal { s.close() }
            localSockets.removeAll()
            pendingLocal.removeAll()
            readBuffer.removeAll()
            sawMagic = false
        }

        private func writeMux(_ data: Data) {
            guard muxFd >= 0 else { return }
            data.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                var sent = 0
                while sent < data.count {
                    let n = Darwin.write(muxFd, base.advanced(by: sent), data.count - sent)
                    if n <= 0 { break }
                    sent += n
                }
            }
        }

        private func pumpFrames() {
            if !sawMagic {
                guard readBuffer.count >= 5 else { return }
                guard readBuffer.prefix(4) == UsbBridge.magic, readBuffer[4] == UsbBridge.version else {
                    dropMux()
                    return
                }
                readBuffer.removeSubrange(0..<5)
                sawMagic = true
            }
            while readBuffer.count >= 9 {
                let ty = readBuffer[0]
                let streamId = UInt32(bigEndianBytes: readBuffer[1..<5])
                let len = Int(UInt32(bigEndianBytes: readBuffer[5..<9]))
                guard len <= 4 * 1024 * 1024 else {
                    dropMux()
                    return
                }
                guard readBuffer.count >= 9 + len else { return }
                let payload = Data(readBuffer[9..<(9 + len)])
                readBuffer.removeSubrange(0..<(9 + len))
                onFrame(ty: ty, streamId: streamId, payload: payload)
            }
        }

        private func onFrame(ty: UInt8, streamId: UInt32, payload: Data) {
            switch ty {
            case UsbBridge.msgHello:
                sendFrame(UsbBridge.msgHelloAck, streamId: 0, payload: Data())
                // Safe to OPEN now that handshake completed.
                flushWaitingLocal()
            case UsbBridge.msgOpenAck:
                if let local = pendingLocal.removeValue(forKey: streamId) {
                    localSockets[streamId] = local
                    local.onData = { [weak self] data in
                        self?.sendFrame(UsbBridge.msgData, streamId: streamId, payload: data)
                    }
                    local.onClose = { [weak self] in
                        self?.sendFrame(UsbBridge.msgClose, streamId: streamId, payload: Data())
                        self?.localSockets.removeValue(forKey: streamId)
                    }
                    local.startReading()
                }
            case UsbBridge.msgOpenFail:
                pendingLocal.removeValue(forKey: streamId)?.close()
            case UsbBridge.msgData:
                localSockets[streamId]?.write(payload)
            case UsbBridge.msgClose:
                localSockets.removeValue(forKey: streamId)?.close()
                pendingLocal.removeValue(forKey: streamId)?.close()
            default:
                break
            }
        }

        private func sendFrame(_ ty: UInt8, streamId: UInt32, payload: Data) {
            var frame = Data(capacity: 9 + payload.count)
            frame.append(ty)
            frame.append(contentsOf: streamId.bigEndianBytes)
            frame.append(contentsOf: UInt32(payload.count).bigEndianBytes)
            frame.append(payload)
            writeMux(frame)
        }
    }

    private final class LocalSocket: @unchecked Sendable {
        private let fd: Int32
        private let queue: DispatchQueue
        var onData: ((Data) -> Void)?
        var onClose: (() -> Void)?
        private var source: DispatchSourceRead?
        private var closed = false

        init(fd: Int32, queue: DispatchQueue) {
            self.fd = fd
            self.queue = queue
            var nodelay: Int32 = 1
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, socklen_t(MemoryLayout.size(ofValue: nodelay)))
        }

        func startReading() {
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in
                guard let self, !self.closed else { return }
                var buf = [UInt8](repeating: 0, count: 16 * 1024)
                let n = Darwin.read(self.fd, &buf, buf.count)
                if n <= 0 {
                    self.close()
                    self.onClose?()
                    return
                }
                self.onData?(Data(buf[0..<n]))
            }
            src.resume()
            source = src
        }

        func write(_ data: Data) {
            guard !closed else { return }
            data.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                var sent = 0
                while sent < data.count {
                    let n = Darwin.write(fd, base.advanced(by: sent), data.count - sent)
                    if n <= 0 { break }
                    sent += n
                }
            }
        }

        func close() {
            guard !closed else { return }
            closed = true
            source?.cancel()
            source = nil
            Darwin.close(fd)
        }
    }
    #endif
}

private extension UInt16 {
    /// Wire big-endian bytes. Do not use `.bigEndian` then shift — on LE hosts
    /// that double-swaps and emits little-endian (breaks OPEN after HELLO_ACK).
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 8) & 0xFF), UInt8(self & 0xFF)]
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF),
        ]
    }

    init(bigEndianBytes bytes: Data.SubSequence) {
        let arr = Array(bytes)
        self = (UInt32(arr[0]) << 24)
            | (UInt32(arr[1]) << 16)
            | (UInt32(arr[2]) << 8)
            | UInt32(arr[3])
    }
}
