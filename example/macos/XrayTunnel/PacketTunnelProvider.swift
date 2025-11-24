import NetworkExtension
import Tun2SocksKit
import os

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private var xrayProcess: Process?
    private var configPath: URL?
    private var apiClient: XrayApiClient?
    
    override func startTunnel(options: [String : NSObject]? = nil) async throws {
        guard
            let protocolConfiguration = protocolConfiguration as? NETunnelProviderProtocol,
            let providerConfiguration = protocolConfiguration.providerConfiguration
        else {
            throw NSError(domain: "XrayTunnel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid protocol configuration"])
        }
        
        guard let xrayConfig: Data = providerConfiguration["xrayConfig"] as? Data,
              let configString = String(data: xrayConfig, encoding: .utf8) else {
            throw NSError(domain: "XrayTunnel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid Xray configuration"])
        }
        
        guard let tunport: Int = parseConfig(jsonData: xrayConfig) else {
            throw NSError(domain: "XrayTunnel", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Xray configuration"])
        }
        
        // Set up tunnel network settings
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")
        settings.mtu = 9000
        settings.ipv4Settings = {
            let settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
            settings.includedRoutes = [NEIPv4Route.default()]
            return settings
        }()
        settings.ipv6Settings = {
            let settings = NEIPv6Settings(addresses: ["fd6e:a81b:704f:1211::1"], networkPrefixLengths: [64])
            settings.includedRoutes = [NEIPv6Route.default()]
            return settings
        }()
        settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "114.114.114.114"])
        try await self.setTunnelNetworkSettings(settings)
        
        // Start Xray process
        try startXRayProcess(config: configString)
        
        // Start SOCKS5 tunnel
        startSocks5Tunnel(serverPort: tunport)
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopXRayProcess()
        Socks5Tunnel.quit()
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if let message = String(data: messageData, encoding: .utf8) {
            if message == "xray_traffic" {
                // Get traffic stats from SOCKS5 tunnel
                let traffic = "\(Socks5Tunnel.stats.up.bytes),\(Socks5Tunnel.stats.down.bytes)"
                completionHandler?(traffic.data(using: .utf8))
            } else if message.hasPrefix("xray_delay") {
                // Measure delay via API
                let url = String(message[message.index(message.startIndex, offsetBy: 10)...])
                let delay = apiClient?.measureDelay(url: url) ?? -1
                completionHandler?("\(delay)".data(using: .utf8))
            } else {
                completionHandler?(messageData)
            }
        } else {
            completionHandler?(messageData)
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        // Xray process will continue running
        completionHandler()
    }
    
    override func wake() {
        // Xray process should still be running
    }
    
    // MARK: - Private Methods
    
    private func startSocks5Tunnel(serverPort port: Int) {
        let config = """
        tunnel:
          mtu: 9000
        socks5:
          port: \(port)
          address: 127.0.0.1
          udp: 'udp'
        misc:
          task-stack-size: 20480
          connect-timeout: 5000
          read-write-timeout: 60000
          log-file: stdout
          log-level: debug
          limit-nofile: 65535
        """
        DispatchQueue.global(qos: .userInitiated).async {
            NSLog("HEV_SOCKS5_TUNNEL_MAIN: \(Socks5Tunnel.run(withConfig: .string(content: config)))")
        }
    }
    
    private func startXRayProcess(config: String) throws {
        // Find Xray executable
        guard let xrayPath = findXrayExecutable() else {
            throw NSError(domain: "XrayTunnel", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Xray executable not found. Please download Xray-core v25.10.15+ from https://github.com/XTLS/Xray-core/releases"
            ])
        }
        
        // Write config to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("xray_config_\(UUID().uuidString).json")
        
        try config.write(to: configFile, atomically: true, encoding: .utf8)
        self.configPath = configFile
        
        // Create and launch process
        let process = Process()
        process.executableURL = xrayPath
        process.arguments = ["-config", configFile.path]
        
        // Set up pipes for output
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // Handle process output
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                NSLog("Xray: \(output)")
            }
        }
        
        // Launch process
        try process.run()
        self.xrayProcess = process
        
        // Wait a bit for Xray to start
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Initialize API client
        self.apiClient = XrayApiClient(address: "127.0.0.1", port: 10085)
        
        NSLog("Xray process started successfully")
    }
    
    private func stopXRayProcess() {
        if let process = xrayProcess, process.isRunning {
            process.terminate()
            
            // Wait for termination with timeout
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if process.isRunning {
                    process.kill()
                }
                group.leave()
            }
            process.waitUntilExit()
            group.wait()
        }
        
        xrayProcess = nil
        apiClient = nil
        
        // Clean up config file
        if let configPath = configPath {
            try? FileManager.default.removeItem(at: configPath)
            self.configPath = nil
        }
        
        NSLog("Xray process stopped")
    }
    
    private func findXrayExecutable() -> URL? {
        let searchPaths = [
            // App bundle (embedded)
            Bundle.main.resourcePath?.appending("/xray") ?? "",
            Bundle.main.resourcePath?.appending("/xray/xray") ?? "",
            
            // Container shared directory (for Network Extension)
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.tfox.flutterVlessExample")?.appendingPathComponent("xray").path ?? "",
            
            // Application Support
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("flutter_vless/xray").path ?? "",
            
            // Home directory
            NSHomeDirectory() + "/.flutter_vless/xray",
            NSHomeDirectory() + "/.xray/xray",
            
            // System paths (if installed via Homebrew)
            "/usr/local/bin/xray",
            "/opt/homebrew/bin/xray",
        ]
        
        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) && isExecutable(url: url) {
                return url
            }
        }
        
        return nil
    }
    
    private func isExecutable(url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        
        return FileManager.default.isExecutableFile(atPath: url.path)
    }
    
    private func parseConfig(jsonData: Data) -> Int? {
        do {
            if let configJSON = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
               let inbounds = configJSON["inbounds"] as? [[String: Any]] {
                for inbound in inbounds {
                    if let protocolType = inbound["protocol"] as? String, let port = inbound["port"] as? Int {
                        switch protocolType {
                        case "socks":
                            return port
                        case "http":
                            return port
                        default:
                            break
                        }
                    }
                }
            }
        } catch {
            NSLog("Failed to parse JSON: \(error.localizedDescription)")
        }
        return nil
    }
}

// MARK: - API Client

class XrayApiClient {
    private let address: String
    private let port: Int
    private let baseURL: String
    
    init(address: String, port: Int) {
        self.address = address
        self.port = port
        self.baseURL = "http://\(address):\(port)"
    }
    
    func measureDelay(url: String) -> Int {
        guard let testURL = URL(string: url) else {
            return -1
        }
        
        let startTime = Date()
        var request = URLRequest(url: testURL)
        request.timeoutInterval = 10.0
        
        let semaphore = DispatchSemaphore(value: 0)
        var delay: Int = -1
        
        URLSession.shared.dataTask(with: request) { _, _, error in
            defer { semaphore.signal() }
            
            if error == nil {
                let elapsed = Date().timeIntervalSince(startTime)
                delay = Int(elapsed * 1000) // Convert to milliseconds
            }
        }.resume()
        
        semaphore.wait()
        return delay
    }
}
