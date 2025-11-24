import Foundation
import Combine
import Darwin   // for kill and SIGKILL

/// Manages Xray-core process execution and API communication
/// Uses Xray-core binary directly (like Windows version) instead of outdated xray-mobile framework
class XrayProcessManager {
    private var xrayProcess: Process?
    private var configPath: URL?
    // private var apiClient: XrayApiClient? // Removed
    private var cancellables = Set<AnyCancellable>()
    
    private let apiAddress = "127.0.0.1"
    private var apiPort = 10085
    
    // Statistics
    @Published var totalUpload: Int64 = 0
    @Published var totalDownload: Int64 = 0
    @Published var uploadSpeed: Int64 = 0
    @Published var downloadSpeed: Int64 = 0
    
    private var statsTimer: Timer?
    private var lastUpload: Int64 = 0
    private var lastDownload: Int64 = 0
    
    private var xrayExecutablePath: URL?

    /// Find Xray executable in common locations
    func findXrayExecutable() -> URL? {
        if let cached = xrayExecutablePath, FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        
        let searchPaths = [
            // Current directory
            FileManager.default.currentDirectoryPath + "/xray",
            FileManager.default.currentDirectoryPath + "/xray/xray",
            
            // App bundle
            Bundle.main.resourcePath?.appending("/xray") ?? "",
            Bundle.main.resourcePath?.appending("/xray/xray") ?? "",
            
            // Application Support
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("flutter_vless/xray").path ?? "",
            
            // Home directory
            NSHomeDirectory() + "/.flutter_vless/xray",
            NSHomeDirectory() + "/.xray/xray",
            
            // /usr/local/bin (if installed via Homebrew)
            "/usr/local/bin/xray",
            "/opt/homebrew/bin/xray",
        ]
        
        NSLog("XrayProcessManager: Starting binary search...")
        for path in searchPaths {
            if path.isEmpty { continue }
            let url = URL(fileURLWithPath: path)
            let exists = FileManager.default.fileExists(atPath: url.path)
            // NSLog("Checking path: %@ - Exists: %@", path, String(exists))
            
            if exists {
                let isExec = isExecutable(url: url)
                // NSLog("  -> Is Executable: %@", String(isExec))
                if isExec {
                    NSLog("  -> FOUND VALID BINARY: %@", path)
                    self.xrayExecutablePath = url
                    return url
                }
            }
        }
        
        NSLog("XrayProcessManager: Xray binary NOT found in any search path.")
        return nil
    }
    
    private func isExecutable(url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        
        // Check if file is executable
        return FileManager.default.isExecutableFile(atPath: url.path)
    }
    
    /// Start Xray with configuration
    @discardableResult
    func start(config: String) throws -> Bool {
        guard let xrayPath = findXrayExecutable() else {
            throw XrayError.executableNotFound
        }
        
        // Validate JSON config
        guard let configData = config.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            throw XrayError.invalidConfig
        }
        
        // Inject API config if missing
        if json["api"] == nil {
            NSLog("XrayProcessManager: 'api' section missing. Injecting default API config.")
            json["api"] = [
                "tag": "api",
                "listen": "127.0.0.1:10085",
                "services": ["HandlerService", "StatsService", "LoggerService"]
            ]
            
            // Also ensure 'stats' object exists
            if json["stats"] == nil {
                json["stats"] = [:]
            }
            
            // Ensure policy enables stats
            if json["policy"] == nil {
                 json["policy"] = [
                    "system": [
                        "statsInboundUplink": true,
                        "statsInboundDownlink": true,
                        "statsOutboundUplink": true,
                        "statsOutboundDownlink": true
                    ]
                ]
            }
        }
        
        // Re-serialize config
        let modifiedConfigData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        let modifiedConfig = String(data: modifiedConfigData, encoding: .utf8) ?? config
        
        // Write config to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("xray_config_\(UUID().uuidString).json")
        
        try modifiedConfig.write(to: configFile, atomically: true, encoding: .utf8)
        self.configPath = configFile
        
        // Create process
        let process = Process()
        process.executableURL = xrayPath
        process.arguments = ["-config", configFile.path]
        
        // Set up pipes for output
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // Capture output for debugging
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                NSLog("[Xray Core]: %@", output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
        // Launch process
        try process.run()
        self.xrayProcess = process
        
        NSLog("XrayProcessManager: Xray started with PID: %d", process.processIdentifier)
        
        // Wait a bit for Xray to start
        Thread.sleep(forTimeInterval: 0.5)
        
        // Initialize API client
        let currentApiPort = parseApiPort(config: modifiedConfig)
        self.apiPort = currentApiPort
        NSLog("XrayProcessManager: API port set to %d", currentApiPort)
        
        // Set system proxy
        setSystemProxy(config: modifiedConfig)
        
        // Start stats monitoring
        startStatsMonitoring()
        
        return true
    }
    
    /// Stop Xray process
    func stop() {
        clearSystemProxy()
        
        statsTimer?.invalidate()
        statsTimer = nil

        if let process = xrayProcess, process.isRunning {
            // Politely ask the process to exit
            process.terminate()

            // Wait and, if still running, force kill with SIGKILL
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if process.isRunning {
                    // processIdentifier is Int32; use POSIX kill to force-kill
                    let pid = process.processIdentifier
                    if pid > 0 {
                        _ = Darwin.kill(pid_t(pid), SIGKILL)
                    }
                }
                group.leave()
            }
            // Wait for the process to exit
            process.waitUntilExit()
            group.wait()
        }

        xrayProcess = nil
        // apiClient = nil

        // Clean up config file
        if let configPath = configPath {
            try? FileManager.default.removeItem(at: configPath)
            self.configPath = nil
        }

        // Reset stats
        totalUpload = 0
        totalDownload = 0
        uploadSpeed = 0
        downloadSpeed = 0
    }
    
    /// Check if Xray is running
    var isRunning: Bool {
        return xrayProcess?.isRunning ?? false
    }
    
    /// Get Xray version
    func getVersion() -> String? {
        guard let xrayPath = findXrayExecutable() else {
            return nil
        }
        
        let process = Process()
        process.executableURL = xrayPath
        process.arguments = ["version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Extract version from output (e.g., "Xray 1.8.0")
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    if line.contains("Xray") || line.contains("xray") {
                        return line.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("Error getting Xray version: \(error)")
        }
        
        return nil
    }
    
    /// Measure server delay
    func measureDelay(url: String) -> Int {
        // TODO: Implement delay measurement via CLI or other means
        return -1
    }
    
    /// Get connected server delay
    func getConnectedServerDelay(url: String) -> Int {
        return measureDelay(url: url)
    }
    
    // MARK: - Private Methods
    
    /// Get list of available network services
    private func getNetworkServices() -> [String] {
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
            NSLog("Error getting network services: %@", error.localizedDescription)
        }
        
        // Fallback to common names if detection fails
        return ["Wi-Fi", "Ethernet"]
    }

    /// Parse API port from config
    private func parseApiPort(config: String) -> Int {
        guard let data = config.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let api = json["api"] as? [String: Any] else {
            return 10085
        }
        
        if let port = api["port"] as? Int {
            return port
        }
        
        if let listen = api["listen"] as? String {
            // Parse "127.0.0.1:10085"
            let components = listen.components(separatedBy: ":")
            if components.count == 2, let port = Int(components[1]) {
                return port
            }
        }
        
        return 10085
    }

    /// Parse SOCKS port from config
    private func parseSocksPort(config: String) -> String {
        guard let data = config.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inbounds = json["inbounds"] as? [[String: Any]] else {
            return "10808"
        }
        
        // Try to find inbound with tag "in_proxy" or protocol "socks"
        for inbound in inbounds {
            if let tag = inbound["tag"] as? String, tag == "in_proxy",
               let port = inbound["port"] as? Int {
                return String(port)
            }
            if let protocolName = inbound["protocol"] as? String, protocolName == "socks",
               let port = inbound["port"] as? Int {
                return String(port)
            }
        }
        
        return "10808"
    }

    /// Set system proxy using networksetup
    private func setSystemProxy(config: String) {
        let services = getNetworkServices()
        let port = parseSocksPort(config: config)
        
        NSLog("XrayProcessManager: Setting system proxy to port %@", port)
        
        for service in services {
            // Set SOCKS proxy
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            task.arguments = ["-setsocksfirewallproxy", service, "127.0.0.1", port]
            try? task.run()
            task.waitUntilExit()
            
            // Enable SOCKS proxy
            let enableTask = Process()
            enableTask.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            enableTask.arguments = ["-setsocksfirewallproxystate", service, "on"]
            try? enableTask.run()
            enableTask.waitUntilExit()
            
            // Set bypass domains (localhost, 127.0.0.1, etc.)
            let bypassTask = Process()
            bypassTask.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            bypassTask.arguments = ["-setproxybypassdomains", service, "localhost", "127.0.0.1", "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12"]
            try? bypassTask.run()
            bypassTask.waitUntilExit()
        }
        NSLog("XrayProcessManager: Attempted to set system proxy for: %@", services.joined(separator: ", "))
    }
    
    /// Clear system proxy
    private func clearSystemProxy() {
        let services = getNetworkServices()
        
        for service in services {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            task.arguments = ["-setsocksfirewallproxystate", service, "off"]
            try? task.run()
            task.waitUntilExit()
        }
        NSLog("XrayProcessManager: Attempted to clear system proxy for: %@", services.joined(separator: ", "))
    }
    
    private func startStatsMonitoring() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    private func updateStats() {
        guard let xrayPath = findXrayExecutable() else {
            NSLog("XrayProcessManager: Cannot update stats - binary not found")
            return
        }
        
        // Use xray api statsquery to get stats
        // Command: xray api statsquery --server=127.0.0.1:10085
        
        let task = Process()
        task.executableURL = xrayPath
        // Add empty string pattern to match all stats
        task.arguments = ["api", "statsquery", "--server=127.0.0.1:\(apiPort)", ""]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        let errorPipe = Pipe()
        task.standardError = errorPipe
        
        do {
            // NSLog("XrayProcessManager: Running stats query...")
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                NSLog("XrayProcessManager: Stats query error: %@", errorOutput)
            }
            
            guard let output = String(data: data, encoding: .utf8) else { return }
            
            // Parse JSON output
            // Format: { "stat": [ { "name": "...", "value": 123 }, ... ] }
            
            var currentUpload: Int64 = 0
            var currentDownload: Int64 = 0
            
            if let jsonData = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let stats = json["stat"] as? [[String: Any]] {
                
                for stat in stats {
                    guard let name = stat["name"] as? String,
                          let value = stat["value"] as? Int64 else {
                        continue
                    }
                    
                    // Only count outbound traffic to avoid double counting (inbound + outbound)
                    // Exclude blackhole (blocked) traffic
                    if name.hasPrefix("outbound>>>") && !name.contains("blackhole") {
                        if name.hasSuffix(">>>uplink") {
                            currentUpload += value
                        } else if name.hasSuffix(">>>downlink") {
                            currentDownload += value
                        }
                    }
                }
            }
            
            // Calculate speeds
            if lastUpload > 0 || lastDownload > 0 {
                uploadSpeed = max(0, currentUpload - lastUpload)
                downloadSpeed = max(0, currentDownload - lastDownload)
            }
            
            totalUpload = currentUpload
            totalDownload = currentDownload
            
            lastUpload = currentUpload
            lastDownload = currentDownload
            
        } catch {
            NSLog("Error querying stats: %@", error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum XrayError: LocalizedError {
    case executableNotFound
    case invalidConfig
    case processStartFailed
    case apiConnectionFailed
    
    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Xray executable not found. Please download Xray-core from https://github.com/XTLS/Xray-core/releases"
        case .invalidConfig:
            return "Invalid Xray configuration JSON"
        case .processStartFailed:
            return "Failed to start Xray process"
        case .apiConnectionFailed:
            return "Failed to connect to Xray API"
        }
    }
}

