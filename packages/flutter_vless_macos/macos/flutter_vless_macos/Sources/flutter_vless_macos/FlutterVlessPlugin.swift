import Foundation
import FlutterMacOS
import AppKit
import NetworkExtension
import Combine

#if canImport(CXRay)
import CXRay
#endif

import os
import CFNetwork
import Darwin

private let pluginLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "flutter_vless.Runner",
    category: "FlutterVlessPlugin"
)

// MARK: - System Proxy Helper (macOS only)
private struct SystemProxyHelper {
    static func getNetworkServices() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-listallnetworkservices"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.contains("*") && $0 != "An asterisk (*) denotes that a network service is disabled." }
            }
        } catch {
            pluginLog.error("Error getting network services: \(error.localizedDescription, privacy: .public)")
        }
        
        return ["Wi-Fi", "Ethernet"] // Fallback
    }

    /// Parses the XRay config to find the proxy inbound port.
    /// Prefers HTTP inbound (tag "http_proxy"), then falls back to SOCKS, then "in_proxy".
    static func parseProxyPort(config: String) -> (httpPort: String?, socksPort: String?) {
        guard let data = config.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inbounds = json["inbounds"] as? [[String: Any]] else {
            return (nil, nil)
        }
        var httpPort: String? = nil
        var socksPort: String? = nil
        for inbound in inbounds {
            let proto = inbound["protocol"] as? String ?? ""
            let tag = inbound["tag"] as? String ?? ""
            guard let port = inbound["port"] as? Int else { continue }
            if proto == "http" || tag == "http_proxy" {
                httpPort = String(port)
            }
            if proto == "socks" || tag == "in_proxy" || tag == "socks" {
                socksPort = String(port)
            }
        }
        return (httpPort, socksPort)
    }

    static func parseOutboundAddresses(config: String) -> [String] {
        var addresses: [String] = []
        guard let data = config.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var rawAddresses: [String] = []
        if let outbounds = json["outbounds"] as? [[String: Any]] {
            for outbound in outbounds {
                if let settings = outbound["settings"] as? [String: Any] {
                    if let vnext = settings["vnext"] as? [[String: Any]] {
                        for server in vnext {
                            if let address = server["address"] as? String, !address.isEmpty {
                                rawAddresses.append(address)
                            }
                        }
                    }
                    if let servers = settings["servers"] as? [[String: Any]] {
                        for server in servers {
                            if let address = server["address"] as? String, !address.isEmpty {
                                rawAddresses.append(address)
                            }
                        }
                    }
                }
            }
        }
        if let outbound = json["outbound"] as? [String: Any] {
            if let settings = outbound["settings"] as? [String: Any] {
                if let vnext = settings["vnext"] as? [[String: Any]] {
                    for server in vnext {
                        if let address = server["address"] as? String, !address.isEmpty {
                            rawAddresses.append(address)
                        }
                    }
                }
                if let servers = settings["servers"] as? [[String: Any]] {
                    for server in servers {
                        if let address = server["address"] as? String, !address.isEmpty {
                            rawAddresses.append(address)
                        }
                    }
                }
            }
        }
        for addr in rawAddresses {
            let resolved = resolveDomainToIPs(addr)
            for r in resolved {
                if !addresses.contains(r) {
                    addresses.append(r)
                }
            }
        }
        return addresses
    }

    static func resolveDomainToIPs(_ domain: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        
        var res: UnsafeMutablePointer<addrinfo>? = nil
        let status = getaddrinfo(domain, nil, &hints, &res)
        guard status == 0, let firstAddr = res else {
            return [domain]
        }
        
        var ips: [String] = []
        var ptr: UnsafeMutablePointer<addrinfo>? = firstAddr
        while ptr != nil {
            guard let info = ptr?.pointee else { break }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(info.ai_addr, info.ai_addrlen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: hostname)
                if !ip.isEmpty {
                    ips.append(ip)
                }
            }
            ptr = info.ai_next
        }
        freeaddrinfo(res)
        
        var result = Array(Set(ips))
        if !result.contains(domain) {
            result.append(domain)
        }
        return result
    }

    /// Configures macOS system proxy settings (HTTP + HTTPS + SOCKS) for all network services.
    ///
    /// ОЧЕНЬ ВАЖНЫЙ НЮАНС (ПРОБЛЕМА QUIC / UDP):
    /// Системные прокси в macOS (networksetup) физически не поддерживают перехват UDP-трафика.
    /// Современные сайты (например, Google, YouTube, ChatGPT, 2ip.ru) по умолчанию используют
    /// протокол HTTP/3 (QUIC), который работает поверх UDP. 
    /// Если браузер отправляет запрос по QUIC, он ПОЛНОСТЬЮ ИГНОРИРУЕТ системный прокси и идёт напрямую!
    /// В результате пользователь видит свой реальный IP-адрес.
    /// 
    /// Единственный способ перехватить весь трафик (включая UDP и QUIC) на macOS/iOS — 
    /// использовать полноценный VPN-туннель (PacketTunnelProvider / NetworkExtension), 
    /// а не Proxy-Only режим. Для локального тестирования VPN-режима необходим платный
    /// Apple Developer Account. В Proxy-Only режиме пользователи могут отключать QUIC
    /// в настройках браузера (например, chrome://flags/#enable-quic), чтобы трафик шел через TCP (Proxy).
    static func setSystemProxy(config: String) {
        let services = getNetworkServices()
        let ports = parseProxyPort(config: config)

        var bypassDomains = ["localhost", "127.0.0.1", "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "*.local"]
        let outbounds = parseOutboundAddresses(config: config)
        for addr in outbounds {
            if !bypassDomains.contains(addr) {
                bypassDomains.append(addr)
            }
        }

        for service in services {
            // Set HTTP proxy (most apps check this)
            if let httpPort = ports.httpPort {
                runNetworkSetup(["-setwebproxy", service, "127.0.0.1", httpPort])
                runNetworkSetup(["-setwebproxystate", service, "on"])
                // Set HTTPS proxy (same HTTP proxy handles CONNECT for HTTPS)
                runNetworkSetup(["-setsecurewebproxy", service, "127.0.0.1", httpPort])
                runNetworkSetup(["-setsecurewebproxystate", service, "on"])
            }

            // Set SOCKS proxy (for apps that support SOCKS5)
            if let socksPort = ports.socksPort {
                runNetworkSetup(["-setsocksfirewallproxy", service, "127.0.0.1", socksPort])
                runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
            }

            // Set bypass domains
            runNetworkSetup(["-setproxybypassdomains", service] + bypassDomains)
        }
        pluginLog.info("System proxy set: HTTP=\(ports.httpPort ?? "none", privacy: .public) SOCKS=\(ports.socksPort ?? "none", privacy: .public) services=\(services.count, privacy: .public)")
    }

    /// Clears ALL system proxy settings (HTTP + HTTPS + SOCKS).
    static func clearSystemProxy() {
        let services = getNetworkServices()
        for service in services {
            runNetworkSetup(["-setwebproxystate", service, "off"])
            runNetworkSetup(["-setsecurewebproxystate", service, "off"])
            runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
        }
        pluginLog.info("System proxy cleared for \(services.count, privacy: .public) services")
    }

    /// Helper to run networksetup commands.
    private static func runNetworkSetup(_ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}

// MARK: - Core Classes

private final class PluginXRayLogger: NSObject, XRayLoggerProtocol {
    func logInput(_ s: String?) {
        if let message = s {
            pluginLog.info("XRay delay probe: \(message, privacy: .public)")
        }
    }
}

private actor ServerDelayRunner {
    private let logger = PluginXRayLogger()

    func measure(config: String, url: String) async -> Int64 {
        do {
            guard URL(string: url) != nil else {
                throw NSError(domain: "FlutterVless", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid probe URL"])
            }

            let proxyPort = Self.findFreePort()
            let delayConfig = try Self.buildDelayConfigData(config: config, proxyPort: proxyPort)

            XRaySetMemoryLimit()
            var startError: NSError?
            let started = XRayStart(delayConfig, logger, &startError)
            guard started else {
                throw startError ?? NSError(domain: "FlutterVless", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to start XRay delay probe"])
            }
            defer {
                XRayStop()
                pluginLog.info("Stopped XRay delay probe")
            }

            pluginLog.info("Started XRay delay probe on HTTP proxy port \(proxyPort, privacy: .public)")
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return try await Self.measureURL(url, proxyPort: proxyPort)
        } catch {
            pluginLog.error("Server delay probe failed: \(error.localizedDescription, privacy: .public)")
            return -1
        }
    }

    private static func buildDelayConfigData(config: String, proxyPort: Int) throws -> Data {
        guard
            let data = config.data(using: .utf8),
            var json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            throw NSError(domain: "FlutterVless", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid XRay config JSON"])
        }

        var inbounds = json["inbounds"] as? [[String: Any]] ?? []
        var hasProxyInbound = false

        for index in inbounds.indices {
            guard
                inbounds[index]["protocol"] as? String == "http" ||
                inbounds[index]["protocol"] as? String == "socks"
            else {
                continue
            }
            inbounds[index]["protocol"] = "http"
            inbounds[index]["port"] = proxyPort
            inbounds[index]["listen"] = "127.0.0.1"
            inbounds[index]["settings"] = [:]
            hasProxyInbound = true
            break
        }

        if !hasProxyInbound {
            inbounds.append([
                "tag": "socks",
                "port": proxyPort,
                "listen": "127.0.0.1",
                "protocol": "http",
                "settings": [:]
            ])
        }

        if var log = json["log"] as? [String: Any] {
            log["access"] = ""
            log["error"] = ""
            log["dnsLog"] = false
            json["log"] = log
        }

        json["inbounds"] = inbounds
        return try JSONSerialization.data(withJSONObject: json, options: [])
    }

    private static func measureURL(_ url: String, proxyPort: Int) async throws -> Int64 {
        guard let probeURL = URL(string: url) else {
            throw NSError(domain: "FlutterVless", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid probe URL"])
        }

        var request = URLRequest(url: probeURL)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 5

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPPort as String: proxyPort,
            "HTTPSEnable": true,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": proxyPort
        ]

        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let start = DispatchTime.now().uptimeNanoseconds
        let (_, response) = try await session.data(for: request)
        let elapsed = (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        if let httpResponse = response as? HTTPURLResponse {
            pluginLog.info("Server delay probe response=\(httpResponse.statusCode, privacy: .public) delay=\(elapsed, privacy: .public)ms")
        } else {
            pluginLog.info("Server delay probe delay=\(elapsed, privacy: .public)ms")
        }
        return Int64(elapsed)
    }

    private static func findFreePort() -> Int {
        let fallbackPort = 10806
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            return fallbackPort
        }
        defer { close(socketDescriptor) }

        var reuse: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            return fallbackPort
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketDescriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            return fallbackPort
        }

        return Int(UInt16(bigEndian: address.sin_port))
    }
}

private final class ProxyOnlyRunner {
    private let logger = PluginXRayLogger()
    private(set) var isRunning = false
    private(set) var connectedDate: Date?
    /// Tracks total bytes uploaded since last start.
    private(set) var totalUpload: Int64 = 0
    /// Tracks total bytes downloaded since last start.
    private(set) var totalDownload: Int64 = 0

    func start(configData: Data, configString: String) throws {
        if isRunning {
            stop()
        }

        let preparedConfig = try Self.buildProxyOnlyConfigData(configData: configData)
        XRaySetMemoryLimit()
        var startError: NSError?
        let started = XRayStart(preparedConfig, logger, &startError)
        guard started else {
            throw startError ?? NSError(domain: "FlutterVless", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to start XRay proxy-only mode"])
        }

        // IMPORTANT: pass preparedConfig (not original configString) so setSystemProxy
        // can see the HTTP inbound that buildProxyOnlyConfigData added.
        let preparedConfigString = String(data: preparedConfig, encoding: .utf8) ?? configString
        SystemProxyHelper.setSystemProxy(config: preparedConfigString)

        isRunning = true
        connectedDate = Date()
        totalUpload = 0
        totalDownload = 0
        pluginLog.info("Started XRay proxy-only mode configBytes=\(preparedConfig.count, privacy: .public)")
    }

    func stop() {
        // Always clear system proxy first — even if isRunning is somehow false,
        // this guarantees we never leave a dead proxy configured.
        SystemProxyHelper.clearSystemProxy()
        guard isRunning else {
            return
        }
        XRayStop()
        isRunning = false
        connectedDate = nil
        totalUpload = 0
        totalDownload = 0
        pluginLog.info("Stopped XRay proxy-only mode")
    }

    /// Unconditional emergency cleanup — called when the process is about to exit.
    /// Does NOT check `isRunning` because the app might crash at any time.
    /// 
    /// ВАЖНО: Если приложение завершится некорректно (краш или принудительная остановка в Xcode)
    /// и системные настройки прокси не будут очищены, на Mac полностью пропадет интернет!
    /// (так как macOS будет пытаться отправлять весь трафик на выключенный локальный порт XRay).
    func forceCleanup() {
        SystemProxyHelper.clearSystemProxy()
        XRayStop()
        isRunning = false
        connectedDate = nil
        pluginLog.info("Force cleanup: cleared system proxy and stopped XRay")
    }

    func measureConnectedDelay(url: String) -> Int64 {
        guard isRunning else {
            return -1
        }
        var error: NSError?
        var delay: Int64 = -1
        XRayMeasureDelay(url, &delay, &error)
        if let error {
            pluginLog.error("Proxy-only connected delay failed: \(error.localizedDescription, privacy: .public)")
            return -1
        }
        return delay
    }

    /// Queries real traffic stats via XRay stats gRPC API.
    func queryTrafficStats() -> (upload: Int64, download: Int64) {
        guard isRunning else { return (0, 0) }
        let raw = XRayQueryStats("") ?? ""
        guard !raw.isEmpty else { return (totalUpload, totalDownload) }
        var up: Int64 = 0
        var down: Int64 = 0
        for line in raw.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: ">>>")
            guard parts.count >= 2, let value = Int64(parts.last!.trimmingCharacters(in: .whitespaces)) else { continue }
            if line.contains("uplink") { up += value }
            else if line.contains("downlink") { down += value }
        }
        totalUpload = up
        totalDownload = down
        return (up, down)
    }

    private static func buildProxyOnlyConfigData(configData: Data) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: configData, options: []) as? [String: Any] else {
            throw NSError(domain: "FlutterVless", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid XRay config JSON"])
        }

        if var log = json["log"] as? [String: Any] {
            log["access"] = ""
            log["error"] = ""
            log["dnsLog"] = false
            json["log"] = log
        } else {
            json["log"] = ["access": "", "error": "", "dnsLog": false, "loglevel": "warning"]
        }

        // Ensure stats are enabled for traffic tracking
        if json["stats"] == nil {
            json["stats"] = [String: Any]()
        }

        // Ensure policy.system.statsOutboundUplink/Downlink are enabled
        var policy = json["policy"] as? [String: Any] ?? [:]
        var system = policy["system"] as? [String: Any] ?? [:]
        system["statsOutboundUplink"] = true
        system["statsOutboundDownlink"] = true
        policy["system"] = system
        json["policy"] = policy

        // Ensure we have both HTTP and SOCKS inbounds for maximum compatibility.
        var inbounds = json["inbounds"] as? [[String: Any]] ?? []
        
        // Check if HTTP inbound exists
        let hasHTTP = inbounds.contains { ($0["protocol"] as? String) == "http" }
        // Check if SOCKS inbound exists
        let hasSOCKS = inbounds.contains {
            let proto = $0["protocol"] as? String
            return proto == "socks"
        }

        // If the config has an "in_proxy" tag with socks/http, use it.
        // Otherwise add our own inbounds.
        if !hasHTTP {
            // Find a free port for HTTP (use SOCKS port + 1 if SOCKS exists)
            let httpPort: Int
            if let existingSOCKS = inbounds.first(where: { ($0["protocol"] as? String) == "socks" }),
               let socksPort = existingSOCKS["port"] as? Int {
                httpPort = socksPort + 1
            } else {
                httpPort = 10809
            }
            
            // ВАЖНО: Мы добавляем HTTP Inbound, так как системные прокси macOS лучше работают
            // с HTTP-прокси (особенно для HTTPS CONNECT запросов). 
            // Также мы ОБЯЗАТЕЛЬНО включаем 'sniffing', чтобы XRay мог извлекать доменные имена
            // (SNI) из трафика. Без sniffing правила маршрутизации по доменам (routing -> domain)
            // работать не будут, и трафик может пойти напрямую.
            inbounds.append([
                "tag": "http_proxy",
                "listen": "127.0.0.1",
                "port": httpPort,
                "protocol": "http",
                "settings": ["allowTransparent": false],
                "sniffing": ["enabled": true, "destOverride": ["http", "tls", "quic"]]
            ])
        }

        if !hasSOCKS && !inbounds.contains(where: { ($0["tag"] as? String) == "in_proxy" }) {
            inbounds.append([
                "tag": "socks",
                "listen": "127.0.0.1",
                "port": 10808,
                "protocol": "socks",
                "settings": ["auth": "noauth", "udp": true]
            ])
        }

        json["inbounds"] = inbounds

        // Inject XRay API service (gRPC on 127.0.0.1:10085) for stats queries.
        // Only add if not already present.
        let hasAPI = (json["api"] as? [String: Any]) != nil
        if !hasAPI {
            json["api"] = [
                "tag": "api",
                "services": ["StatsService"]
            ]
            // Add routing rule to direct API traffic to the API inbound
            var routing = json["routing"] as? [String: Any] ?? ["domainStrategy": "AsIs"]
            var rules = routing["rules"] as? [[String: Any]] ?? []
            // Prepend the API rule so it takes priority
            let apiRule: [String: Any] = [
                "type": "field",
                "inboundTag": ["api"],
                "outboundTag": "api"
            ]
            rules.insert(apiRule, at: 0)
            routing["rules"] = rules
            json["routing"] = routing

            // Add the API inbound listener on 10085
            inbounds.append([
                "tag": "api",
                "listen": "127.0.0.1",
                "port": 10085,
                "protocol": "dokodemo-door",
                "settings": ["address": "127.0.0.1"]
            ])
            json["inbounds"] = inbounds

            // ВАЖНО: Если мы добавили правило маршрутизации с `outboundTag: "api"`,
            // мы ОБЯЗАНЫ добавить outbound с тегом "api" в конфигурацию!
            // Если XRay встретит правило маршрутизации, ссылающееся на несуществующий outbound,
            // его внутренний роутер (dispatcher) может начать сбрасывать весь трафик.
            // Если XRay начнет сбрасывать (drop) TCP-соединения, браузеры (Chrome, Safari)
            // решат, что прокси "мертв", и автоматически начнут слать трафик напрямую (fallback to direct).
            var outbounds = json["outbounds"] as? [[String: Any]] ?? []
            if !outbounds.contains(where: { ($0["tag"] as? String) == "api" }) {
                outbounds.append([
                    "tag": "api",
                    "protocol": "freedom",
                    "settings": [:]
                ])
                json["outbounds"] = outbounds
            }
        }

        return try JSONSerialization.data(withJSONObject: json, options: [])
    }
}

public class FlutterVlessPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var packetTunnelManager: PacketTunnelManager? = nil
    private let serverDelayRunner = ServerDelayRunner()
    private let proxyOnlyRunner = ProxyOnlyRunner()

    private var timer: Timer?
    private var eventSink: FlutterEventSink?
    private var totalUpload: Int = 0
    private var totalDownload: Int = 0
    private var uploadSpeed: Int = 0
    private var downloadSpeed: Int = 0
    private var lastTrafficLogDate: Date = .distantPast
    private var lastProviderDebugLogDate: Date = .distantPast

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_vless", binaryMessenger: registrar.messenger)
        let instance = FlutterVlessPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        let eventChannel = FlutterEventChannel(name: "flutter_vless/status", binaryMessenger: registrar.messenger)
        eventChannel.setStreamHandler(instance)

        // CRITICAL: Register for app termination to clean up system proxy.
        // Without this, closing the app while connected leaves a dead SOCKS proxy
        // configured in System Preferences, which kills all network traffic.
        NotificationCenter.default.addObserver(
            instance,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        // Also handle unexpected termination signals
        instance.installSignalHandlers()
        pluginLog.info("FlutterVlessPlugin registered with app termination cleanup")
    }

    /// Called when the application is about to terminate (Cmd+Q, Xcode stop, etc.).
    @objc private func applicationWillTerminate(_ notification: Notification) {
        pluginLog.info("Application will terminate — cleaning up proxy settings")
        proxyOnlyRunner.forceCleanup()
        stopTimer()
    }

    /// Installs POSIX signal handlers so that even SIGTERM/SIGINT clears the proxy.
    private func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { signal in
            SystemProxyHelper.clearSystemProxy()
            // Re-raise the signal with default handler
            Darwin.signal(signal, SIG_DFL)
            Darwin.raise(signal)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
    }

    deinit {
        proxyOnlyRunner.forceCleanup()
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        pluginLog.info("FlutterVlessPlugin deinit — cleanup completed")
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        pluginLog.info("Status stream attached")
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        pluginLog.info("Status stream detached")
        self.eventSink = nil
        return nil
    }

    private func startTimer() {
        pluginLog.info("Starting traffic polling timer")
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [weak self] _ in
            guard let self = self else { return }
            if self.proxyOnlyRunner.isRunning {
                let elapsed = Date().timeIntervalSince(self.proxyOnlyRunner.connectedDate ?? Date())
                let seconds = Int(elapsed)
                // Query real traffic stats from XRay stats API
                let stats = self.proxyOnlyRunner.queryTrafficStats()
                let currentUp = stats.upload
                let currentDown = stats.download
                let upSpeed = max(0, currentUp - Int64(self.totalUpload))
                let downSpeed = max(0, currentDown - Int64(self.totalDownload))
                self.totalUpload = Int(currentUp)
                self.totalDownload = Int(currentDown)
                self.uploadSpeed = Int(upSpeed)
                self.downloadSpeed = Int(downSpeed)
                self.eventSink?(["\(seconds)", "\(self.uploadSpeed)", "\(self.downloadSpeed)", "\(self.totalUpload)", "\(self.totalDownload)", "CONNECTED"])
                return
            }

            let elapsed = Date().timeIntervalSince(self.packetTunnelManager?.connectedDate ?? Date())
            let seconds = Int(elapsed)
            self.eventSink?(["\(seconds)", "\(self.uploadSpeed)", "\(self.downloadSpeed)", "\(self.totalUpload)", "\(self.totalDownload)", "CONNECTED"])
            Task{
                do{
                    let response =  try await self.packetTunnelManager?.sendProviderMessage(data: "xray_traffic".data(using: .utf8)!)
                    if response != nil{
                        let traffic = String(decoding: response!, as: UTF8.self)
                        let parts = traffic.split(separator: ",")
                        if let up = Int(parts[0]), let down = Int(parts[1]) {
                            self.uploadSpeed = up - self.totalUpload
                            self.downloadSpeed = down - self.totalDownload
                            self.totalUpload = up
                            self.totalDownload = down
                            if Date().timeIntervalSince(self.lastTrafficLogDate) >= 5 {
                                self.lastTrafficLogDate = Date()
                                pluginLog.info("Traffic stats up=\(up, privacy: .public) down=\(down, privacy: .public) upSpeed=\(self.uploadSpeed, privacy: .public) downSpeed=\(self.downloadSpeed, privacy: .public)")
                                self.logProviderDebugSnapshot()
                            }
                        }
                    }
                }catch{
                    pluginLog.error("Error polling traffic: \(error.localizedDescription, privacy: .public)")
                }
            }
        })
    }

    private func stopTimer() {
        pluginLog.info("Stopping traffic polling timer")
        self.timer?.invalidate()
        self.timer = nil
        self.eventSink?(["0", "0", "0", "0", "0", "DISCONNECTED"])
        self.uploadSpeed = 0
        self.downloadSpeed = 0
        self.totalUpload = 0
        self.totalDownload = 0
        self.lastProviderDebugLogDate = .distantPast
    }

    private func logProviderDebugSnapshot() {
        guard Date().timeIntervalSince(lastProviderDebugLogDate) >= 5 else {
            return
        }
        lastProviderDebugLogDate = Date()
        Task {
            do {
                guard let response = try await self.packetTunnelManager?.sendProviderMessage(data: "xray_debug".data(using: .utf8)!) else {
                    pluginLog.warning("Provider debug snapshot unavailable")
                    return
                }
                let snapshot = String(decoding: response, as: UTF8.self)
                if !snapshot.isEmpty {
                    pluginLog.info("Provider debug snapshot:\n\(snapshot, privacy: .public)")
                }
            } catch {
                pluginLog.error("Provider debug snapshot failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        pluginLog.info("Method call: \(call.method, privacy: .public)")
        switch call.method {
        case "requestPermission":
            requestPermission(result: result)
        case "initializeVless":
            initializeVless(call: call, result: result)
        case "startVless":
            startVless(call: call, result: result)
        case "stopVless":
            stopVless(result: result)
        case "getCoreVersion":
            getCoreVersion(result: result)
        case "getConnectedServerDelay":
            getConnectedServerDelay(call: call, result: result)
        case "getServerDelay":
            getServerDelay(call: call, result: result)
        case "getProviderDebugSnapshot":
            getProviderDebugSnapshot(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func stopVless(result: FlutterResult) {
        pluginLog.info("stopVless requested")
        proxyOnlyRunner.stop()
        packetTunnelManager?.stop()
        stopTimer()
        result(nil)
    }

    private func getConnectedServerDelay(call: FlutterMethodCall, result: @escaping FlutterResult){
        guard let arguments = call.arguments as? [String: Any],
              let url = arguments["url"] as? String else{
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for getConnectedServerDelay.", details: nil))
            return
        }
        Task {
            do {
                if self.proxyOnlyRunner.isRunning {
                    let delay = self.proxyOnlyRunner.measureConnectedDelay(url: url)
                    result(Int(delay))
                    return
                }
                let delay = try await packetTunnelManager?.sendProviderMessage(data: "xray_delay\(url)".data(using: .utf8)!) ?? "-1".data(using: .utf8)!
                pluginLog.info("Connected delay response: \(String(decoding: delay, as: UTF8.self), privacy: .public)")
                result(Int(String(decoding: delay, as: UTF8.self)))
            }catch{
                pluginLog.error("Connected delay failed: \(error.localizedDescription, privacy: .public)")
                result(-1)
            }
        }
    }

    private func getProviderDebugSnapshot(result: @escaping FlutterResult) {
        Task {
            do {
                guard let response = try await packetTunnelManager?.sendProviderMessage(data: "xray_debug".data(using: .utf8)!) else {
                    result("")
                    return
                }
                result(String(decoding: response, as: UTF8.self))
            } catch {
                pluginLog.error("Provider debug snapshot request failed: \(error.localizedDescription, privacy: .public)")
                result(FlutterError(code: "PROVIDER_DEBUG_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func getServerDelay(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let url = arguments["url"] as? String,
              let config = arguments["config"] as? String else{
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for getServerDelay.", details: nil))
            return
        }
        Task {
            let delay = await serverDelayRunner.measure(config: config, url: url)
            result(delay)
        }
    }

    private func startVless(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let remark = arguments["remark"] as? String,
              let config = arguments["config"] as? String,
              let configData = config.data(using: .utf8) else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for startVless.", details: nil))
            return
        }
        let proxyOnly = arguments["proxy_only"] as? Bool ?? false
        if proxyOnly {
            do {
                try proxyOnlyRunner.start(configData: configData, configString: config)
                pluginLog.info("Proxy-only start requested successfully remark=\(remark, privacy: .public)")
                startTimer()
                result(nil)
            } catch {
                pluginLog.error("Failed to start proxy-only mode: \(error.localizedDescription, privacy: .public)")
                result(FlutterError(code: "PROXY_ONLY_ERROR",
                                    message: "Failed to start proxy-only mode: \(error.localizedDescription)",
                                    details: nil))
            }
            return
        }

        proxyOnlyRunner.stop()
        packetTunnelManager?.remark = remark
        packetTunnelManager?.xrayConfig = configData
        packetTunnelManager?.bypassSubnets = arguments["bypass_subnets"] as? [String] ?? []
        packetTunnelManager?.proxyOnly = false
        pluginLog.info("startVless remark=\(remark, privacy: .public) configBytes=\(configData.count, privacy: .public) proxyOnly=\(self.packetTunnelManager?.proxyOnly ?? false, privacy: .public) bypassCount=\(self.packetTunnelManager?.bypassSubnets.count ?? 0, privacy: .public)")
        
        Task {
            do {
                try await packetTunnelManager?.saveToPreferences()
                try await packetTunnelManager?.start()
                pluginLog.info("VPN start requested successfully")
                result(nil)
                return
            } catch {
                pluginLog.error("Failed to start VPN: \(error.localizedDescription, privacy: .public)")
                result(FlutterError(code: "VPN_ERROR",
                                    message: "Failed to start VPN: \(error.localizedDescription)",
                                    details: nil))
                stopTimer()
                return
            }
        }
        startTimer()
    }

    private func requestPermission(result: @escaping FlutterResult) {
        Task {
            let isGranted = await packetTunnelManager?.testSaveAndLoadProfile() ?? false
            pluginLog.info("requestPermission result=\(isGranted, privacy: .public)")
            result(isGranted)
        }
    }

    private func getCoreVersion(result: @escaping FlutterResult) {
        Task {
            let version = String(cString: XRayGetVersion())
            pluginLog.info("XRay core version: \(version, privacy: .public)")
            result(version)
        }
    }

    private func initializeVless(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let providerBundleIdentifier = arguments["providerBundleIdentifier"] as? String,
              let groupIdentifier = arguments["groupIdentifier"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for initializeVless.", details: nil))
            return
        }
        pluginLog.info("initializeVless providerBundleIdentifier=\(providerBundleIdentifier, privacy: .public) groupIdentifier=\(groupIdentifier, privacy: .public)")
        self.packetTunnelManager = PacketTunnelManager(providerBundleIdentifier: "\(providerBundleIdentifier).XrayTunnel", groupIdentifier: groupIdentifier)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.packetTunnelManager?.connectedDate != nil{
                self.startTimer()
            }
        }
        result(nil)
    }
}

final class PacketTunnelManager: ObservableObject {
    var providerBundleIdentifier: String?
    var groupIdentifier: String?
    var remark: String = "Xray"
    var xrayConfig: Data = "".data(using: .utf8)!
    var bypassSubnets: [String] = []
    var proxyOnly: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    @Published private var manager: NETunnelProviderManager?

    @Published private(set) var isProcessing: Bool = false

    var status: NEVPNStatus? {
        manager.flatMap { $0.connection.status }
    }

    var connectedDate: Date? {
        manager.flatMap { $0.connection.connectedDate }
    }

    init(providerBundleIdentifier: String, groupIdentifier: String) {
        self.providerBundleIdentifier = providerBundleIdentifier
        self.groupIdentifier = groupIdentifier
        isProcessing = true
        Task(priority: .userInitiated) {
            await self.reload()
            await MainActor.run {
                self.isProcessing = false
            }
        }
    }

    func reload() async {
        self.cancellables.removeAll()
        self.manager = await self.loadTunnelProviderManager()
        pluginLog.info("Reloaded tunnel manager: \(self.manager != nil, privacy: .public)")
        NotificationCenter.default
            .publisher(for: .NEVPNConfigurationChange, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in
                pluginLog.info("NEVPNConfigurationChange received")
                Task(priority: .high) {
                    self.manager = await self.loadTunnelProviderManager()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: .NEVPNStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in
                pluginLog.info("NEVPNStatusDidChange status=\(self.status?.rawValue ?? -1, privacy: .public)")
                objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func saveToPreferences() async throws {
        guard let providerBundleIdentifier = providerBundleIdentifier else {
            throw NSError(domain: "VPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Provider bundle identifier is missing."])
        }

        do {
            let manager = self.manager ?? NETunnelProviderManager()
            self.manager = manager
            manager.localizedDescription = remark
            manager.protocolConfiguration = {
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = providerBundleIdentifier
                configuration.serverAddress = "Xray"
                configuration.providerConfiguration = [
                    "xrayConfig": self.xrayConfig,
                    "bypassSubnets": self.bypassSubnets,
                    "proxyOnly": self.proxyOnly
                ]
                if #available(macOS 11.0, *) {
                    configuration.excludeLocalNetworks = true
                } else {
                    // Fallback
                }
                return configuration
            }()
            manager.isEnabled = true
            pluginLog.info("Saving VPN preferences provider=\(providerBundleIdentifier, privacy: .public) configBytes=\(self.xrayConfig.count, privacy: .public)")
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            pluginLog.info("VPN preferences saved and reloaded")
        } catch {
            pluginLog.error("Error saving VPN preferences: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func removeFromPreferences() async throws {
        guard let manager = manager else {
            return
        }
        pluginLog.info("Removing VPN preferences")
        try await manager.removeFromPreferences()
    }

    func start() async throws {
        guard let manager = manager else {
            throw NSError(domain: "VPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager not found"])
        }

        if !manager.isEnabled {
            manager.isEnabled = true
            try await manager.saveToPreferences()
        }

        do {
            pluginLog.info("Calling startVPNTunnel currentStatus=\(manager.connection.status.rawValue, privacy: .public)")
            try manager.connection.startVPNTunnel()
            pluginLog.info("startVPNTunnel returned currentStatus=\(manager.connection.status.rawValue, privacy: .public)")
        } catch {
            pluginLog.error("Failed to start VPN tunnel: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func stop() {
        guard let manager = manager else {
            return
        }
        pluginLog.info("Calling stopVPNTunnel currentStatus=\(manager.connection.status.rawValue, privacy: .public)")
        manager.connection.stopVPNTunnel()
    }

    @discardableResult
    func sendProviderMessage(data: Data) async throws -> Data? {
        guard let manager = manager else {
            pluginLog.warning("sendProviderMessage skipped: manager is nil")
            return nil
        }

        guard let session = manager.connection as? NETunnelProviderSession else {
            pluginLog.error("sendProviderMessage failed: invalid connection type")
            throw NSError(domain: "VPN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid connection type"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(data) { response in
                    continuation.resume(with: .success(response))
                }
            } catch {
                continuation.resume(with: .failure(error))
            }
        }
    }

    func testSaveAndLoadProfile() async -> Bool {
        do {
            try await saveToPreferences()
            let _ = await loadTunnelProviderManager()
            pluginLog.info("testSaveAndLoadProfile succeeded")
            return true
        } catch {
            pluginLog.error("Error during save and load test: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func loadTunnelProviderManager() async -> NETunnelProviderManager? {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            pluginLog.info("Loaded \(managers.count, privacy: .public) tunnel manager(s) from preferences")

            guard let reval = managers.first(where: {
                guard let configuration = $0.protocolConfiguration as? NETunnelProviderProtocol else {
                    return false
                }
                return configuration.providerBundleIdentifier == providerBundleIdentifier
            }) else {
                pluginLog.warning("No tunnel manager found for provider=\(self.providerBundleIdentifier ?? "nil", privacy: .public)")
                return nil
            }

            try await reval.loadFromPreferences()
            pluginLog.info("Loaded matching tunnel manager enabled=\(reval.isEnabled, privacy: .public) status=\(reval.connection.status.rawValue, privacy: .public)")
            return reval
        } catch {
            pluginLog.error("Error loading tunnel provider manager: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
