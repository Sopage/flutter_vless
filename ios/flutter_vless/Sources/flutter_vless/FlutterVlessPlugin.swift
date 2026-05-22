import Flutter
import UIKit
import NetworkExtension
import Combine
import XRay
import os

private let pluginLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "flutter_vless.Runner",
    category: "FlutterVlessPlugin"
)

public class FlutterVlessPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var packetTunnelManager: PacketTunnelManager? = nil

    private var timer: Timer?
    private var eventSink: FlutterEventSink?
    private var totalUpload: Int = 0
    private var totalDownload: Int = 0
    private var uploadSpeed: Int = 0
    private var downloadSpeed: Int = 0
    private var lastTrafficLogDate: Date = .distantPast
    private var lastProviderDebugLogDate: Date = .distantPast

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_vless", binaryMessenger: registrar.messenger())
        let instance = FlutterVlessPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        let eventChannel = FlutterEventChannel(name: "flutter_vless/status", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
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
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { _ in
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
            var error: NSError?
            var delay: Int64 = -1
            XRayMeasureOutboundDelay(config, url, &delay, &error)
            if let error {
                pluginLog.error("Outbound delay failed: \(error.localizedDescription, privacy: .public)")
            } else {
                pluginLog.info("Outbound delay result: \(delay, privacy: .public)")
            }
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
        packetTunnelManager?.remark = remark
        packetTunnelManager?.xrayConfig = configData
        packetTunnelManager?.bypassSubnets = arguments["bypass_subnets"] as? [String] ?? []
        packetTunnelManager?.proxyOnly = arguments["proxy_only"] as? Bool ?? false
        pluginLog.info("startVless remark=\(remark, privacy: .public) configBytes=\(configData.count, privacy: .public) proxyOnly=\(self.packetTunnelManager?.proxyOnly ?? false, privacy: .public) bypassCount=\(self.packetTunnelManager?.bypassSubnets.count ?? 0, privacy: .public)")
        pluginLog.info("\(self.describeConfig(configData), privacy: .public)")
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
            let version = XRayGetVersion()
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

    private func describeConfig(_ data: Data) -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let inbounds = json["inbounds"] as? [[String: Any]],
            let outbounds = json["outbounds"] as? [[String: Any]]
        else {
            return "Config summary unavailable"
        }
        let inboundSummary = inbounds.compactMap { inbound -> String? in
            guard let proto = inbound["protocol"] as? String else { return nil }
            return "\(proto):\(inbound["port"] ?? "?")"
        }.joined(separator: ",")
        let outboundSummary = outbounds.enumerated().map { index, outbound -> String in
            let tag = outbound["tag"] as? String ?? "\(index)"
            let proto = outbound["protocol"] as? String ?? "?"
            let stream = outbound["streamSettings"] as? [String: Any]
            let network = stream?["network"] as? String ?? "?"
            let security = stream?["security"] as? String ?? "?"
            let hasXhttpExtra = ((stream?["xhttpSettings"] as? [String: Any])?["extra"] != nil)
            return "\(tag)/\(proto)/\(network)/\(security)/xhttpExtra=\(hasXhttpExtra)"
        }.joined(separator: ",")
        return "Config summary inbounds=[\(inboundSummary)] outbounds=[\(outboundSummary)]"
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
                if #available(iOS 14.2, *) {
                    configuration.excludeLocalNetworks = true
                } else {
                    // Fallback on earlier versions
                }
                return configuration
            }()
            manager.isEnabled = true
            pluginLog.info("Saving VPN preferences provider=\(providerBundleIdentifier, privacy: .public) configBytes=\(self.xrayConfig.count, privacy: .public) bypassCount=\(self.bypassSubnets.count, privacy: .public) proxyOnly=\(self.proxyOnly, privacy: .public)")
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
            try  manager.connection.startVPNTunnel()
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

    func testSaveAndLoadProfile() async -> Bool{
        do {
            try await saveToPreferences()

            // Now reload the manager after saving
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
