import Foundation
import Combine
import Darwin   // for kill and SIGKILL

/// Manages Xray-core process execution and API communication
/// Uses Xray-core binary directly (like Windows version) instead of outdated xray-mobile framework
class XrayProcessManager {
    private var xrayProcess: Process?
    private var configPath: URL?
    private var apiClient: XrayApiClient?
    private var cancellables = Set<AnyCancellable>()
    
    private let apiAddress = "127.0.0.1"
    private let apiPort = 10085
    
    // Statistics
    @Published var totalUpload: Int64 = 0
    @Published var totalDownload: Int64 = 0
    @Published var uploadSpeed: Int64 = 0
    @Published var downloadSpeed: Int64 = 0
    
    private var statsTimer: Timer?
    private var lastUpload: Int64 = 0
    private var lastDownload: Int64 = 0
    
    /// Find Xray executable in common locations
    func findXrayExecutable() -> URL? {
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
            NSLog("Checking path: %@ - Exists: %@", path, String(exists))
            
            if exists {
                let isExec = isExecutable(url: url)
                NSLog("  -> Is Executable: %@", String(isExec))
                if isExec {
                    NSLog("  -> FOUND VALID BINARY: %@", path)
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
              let _ = try? JSONSerialization.jsonObject(with: configData) else {
            throw XrayError.invalidConfig
        }
        
        // Write config to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("xray_config_\(UUID().uuidString).json")
        
        try config.write(to: configFile, atomically: true, encoding: .utf8)
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
        self.apiClient = XrayApiClient(address: apiAddress, port: apiPort)
        
        // Set system proxy
        setSystemProxy(config: config)
        
        // Start stats monitoring
        startStatsMonitoring()
        
        return true
    }
    
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
    apiClient = nil

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
    // func stop() {
    //     statsTimer?.invalidate()
    //     statsTimer = nil
        
    //     if let process = xrayProcess, process.isRunning {
    //         process.terminate()
            
    //         // Wait for termination with timeout
    //         let group = DispatchGroup()
    //         group.enter()
    //         DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
    //             if process.isRunning {
    //                 process.kill()
    //             }
    //             group.leave()
    //         }
    //         process.waitUntilExit()
    //         group.wait()
    //     }
        
    //     xrayProcess = nil
    //     apiClient = nil
        
    //     // Clean up config file
    //     if let configPath = configPath {
    //         try? FileManager.default.removeItem(at: configPath)
    //         self.configPath = nil
    //     }
        
    //     // Reset stats
    //     totalUpload = 0
    //     totalDownload = 0
    //     uploadSpeed = 0
    //     downloadSpeed = 0
    // }
    
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
        return apiClient?.measureDelay(url: url) ?? -1
    }
    
    /// Get connected server delay
    func getConnectedServerDelay(url: String) -> Int {
        return measureDelay(url: url)
    }
    
    // MARK: - Private Methods
    
    private func startStatsMonitoring() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    private func updateStats() {
        guard let apiClient = apiClient else { return }
        
        let stats = apiClient.getStats()
        
        let currentUpload = stats["inbound>>>downlink>>>traffic>>>uplink"] ?? 0
        let currentDownload = stats["inbound>>>downlink>>>traffic>>>downlink"] ?? 0
        
        // Calculate speeds
        if lastUpload > 0 || lastDownload > 0 {
            uploadSpeed = max(0, currentUpload - lastUpload)
            downloadSpeed = max(0, currentDownload - lastDownload)
        }
        
        totalUpload = currentUpload
        totalDownload = currentDownload
        
        lastUpload = currentUpload
        lastDownload = currentDownload
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
    
    /// Get traffic statistics
    func getStats() -> [String: Int64] {
        var stats: [String: Int64] = [:]
        
        guard let url = URL(string: "\(baseURL)/api/stats?reset=false") else {
            return stats
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        
        let semaphore = DispatchSemaphore(value: 0)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            
            for (key, value) in json {
                if let intValue = value as? Int64 {
                    stats[key] = intValue
                } else if let intValue = value as? Int {
                    stats[key] = Int64(intValue)
                }
            }
        }.resume()
        
        semaphore.wait()
        return stats
    }
    
    /// Measure delay through Xray
    func measureDelay(url: String) -> Int {
        guard let _ = URL(string: "\(baseURL)/api/stats?reset=false") else {
            return -1
        }
        
        // For delay measurement, we need to make a request through Xray
        // This is a simplified implementation
        // In production, you might want to use Xray's built-in delay measurement
        
        let startTime = Date()
        var request = URLRequest(url: URL(string: url)!)
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

