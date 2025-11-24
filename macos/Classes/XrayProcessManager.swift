import Foundation
import Combine
import Darwin // Required for low-level process control (kill, SIGKILL)

/// **XrayProcessManager**
///
/// Manages the lifecycle and communication with the Xray-core binary on macOS.
///
/// **Architecture Overview:**
/// Unlike mobile implementations that might use shared libraries, this macOS implementation
/// manages Xray as a separate child process. This approach mimics the Windows implementation
/// and offers several advantages:
/// - **Stability:** If Xray crashes, it doesn't take down the main app.
/// - **Updates:** The binary can be swapped independently of the app bundle.
/// - **Isolation:** Clean separation of concerns between UI and core logic.
///
/// **Key Responsibilities:**
/// 1. **Binary Management:** Locates, validates, and executes the `xray` binary.
/// 2. **Configuration Injection:** Dynamically injects API and Stats configurations into the user's JSON config
///    to ensure the app can monitor traffic and control the process, regardless of the user's settings.
/// 3. **System Proxy Integration:** Uses `networksetup` to automatically configure macOS system proxy settings
///    (SOCKS5) for all active network services.
/// 4. **Statistics Monitoring:** Periodically queries the Xray API (via CLI) to retrieve real-time traffic data.
///
/// - Note: This class uses `Process` (NSTask) for execution and `Pipe` for IPC.
class XrayProcessManager {
    
    // MARK: - Private Properties
    
    /// The active Xray process. `nil` if not running.
    private var xrayProcess: Process?
    
    /// URL to the temporary configuration file used to launch Xray.
    private var configPath: URL?
    
    /// Set of cancellables for Combine subscriptions (if needed in future extensions).
    private var cancellables = Set<AnyCancellable>()
    
    /// The local address for the Xray API.
    private let apiAddress = "127.0.0.1"
    
    /// The port used for the Xray API.
    /// This is dynamically parsed from the config or defaults to 10085.
    private var apiPort = 10085
    
    /// The SOCKS5 port used for the local proxy.
    /// This is dynamically parsed from the config or defaults to 10808.
    private var socksPort = 10808
    
    /// Cached path to the validated Xray binary to avoid repeated file system lookups.
    private var xrayExecutablePath: URL?
    
    // MARK: - Public Statistics
    
    // Published properties allow SwiftUI or Combine observers to react to changes.
    
    /// Total bytes uploaded since the session started.
    @Published var totalUpload: Int64 = 0
    
    /// Total bytes downloaded since the session started.
    @Published var totalDownload: Int64 = 0
    
    /// Current upload speed in bytes per second.
    @Published var uploadSpeed: Int64 = 0
    
    /// Current download speed in bytes per second.
    @Published var downloadSpeed: Int64 = 0
    
    // MARK: - Internal State
    
    /// Timer for periodic stats polling.
    private var statsTimer: Timer?
    
    /// Snapshot of upload bytes from the previous poll, used to calculate speed.
    private var lastUpload: Int64 = 0
    
    /// Snapshot of download bytes from the previous poll, used to calculate speed.
    private var lastDownload: Int64 = 0
    
    // MARK: - Binary Management
    
    /// Locates the Xray executable in common locations.
    ///
    /// This method checks a prioritized list of paths, including the app bundle,
    /// Application Support directory, and standard system paths.
    ///
    /// - Returns: A file URL to the executable if found and executable; otherwise `nil`.
    func findXrayExecutable() -> URL? {
        // Return cached path if available and valid
        if let cached = xrayExecutablePath, FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        
        let searchPaths = [
            // 1. Current working directory (useful for development)
            FileManager.default.currentDirectoryPath + "/xray",
            FileManager.default.currentDirectoryPath + "/xray/xray",
            
            // 2. App Bundle Resources (production distribution)
            Bundle.main.resourcePath?.appending("/xray") ?? "",
            Bundle.main.resourcePath?.appending("/xray/xray") ?? "",
            
            // 3. Application Support (user-installed or updated binaries)
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("flutter_vless/xray").path ?? "",
            
            // 4. User Home Directory (hidden folders)
            NSHomeDirectory() + "/.flutter_vless/xray",
            NSHomeDirectory() + "/.xray/xray",
            
            // 5. System Paths (Homebrew, etc.)
            "/usr/local/bin/xray",
            "/opt/homebrew/bin/xray",
        ]
        
        NSLog("XrayProcessManager: Starting binary search...")
        
        for path in searchPaths {
            if path.isEmpty { continue }
            let url = URL(fileURLWithPath: path)
            
            if FileManager.default.fileExists(atPath: url.path) {
                if isExecutable(url: url) {
                    NSLog("  -> FOUND VALID BINARY: %@", path)
                    self.xrayExecutablePath = url
                    return url
                }
            }
        }
        
        NSLog("XrayProcessManager: Xray binary NOT found in any search path.")
        return nil
    }
    
    /// Verifies if a file at the given URL is executable.
    ///
    /// - Parameter url: The file URL to check.
    /// - Returns: `true` if the file exists and is executable.
    private func isExecutable(url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }
    
    // MARK: - Lifecycle Management
    
    /// Starts the Xray process with the provided configuration.
    ///
    /// This method performs several critical steps:
    /// 1. Validates the binary existence.
    /// 2. Parses and modifies the user's JSON config to inject necessary API and Stats settings.
    /// 3. Writes the modified config to a temporary file.
    /// 4. Launches the Xray process.
    /// 5. Configures the system proxy.
    /// 6. Starts the statistics monitoring loop.
    ///
    /// - Parameter config: The raw JSON configuration string.
    /// - Returns: `true` if started successfully.
    /// - Throws: `XrayError` if startup fails.
    @discardableResult
    func start(config: String) throws -> Bool {
        guard let xrayPath = findXrayExecutable() else {
            throw XrayError.executableNotFound
        }
        
        // 1. Validate and Parse Config
        guard let configData = config.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            throw XrayError.invalidConfig
        }
        
        // 2. Inject API Configuration (Critical for Stats)
        // We ensure the API section exists so we can query stats later.
        if json["api"] == nil {
            NSLog("XrayProcessManager: 'api' section missing. Injecting default API config.")
            json["api"] = [
                "tag": "api",
                "listen": "127.0.0.1:10085",
                "services": ["HandlerService", "StatsService", "LoggerService"]
            ]
            
            // Ensure 'stats' object exists
            if json["stats"] == nil {
                json["stats"] = [:]
            }
            
            // Ensure policy enables stats for system traffic
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
        
        // 3. Serialize Modified Config
        let modifiedConfigData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        let modifiedConfig = String(data: modifiedConfigData, encoding: .utf8) ?? config
        
        // 4. Write to Temporary File
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("xray_config_\(UUID().uuidString).json")
        try modifiedConfig.write(to: configFile, atomically: true, encoding: .utf8)
        self.configPath = configFile
        
        // 5. Launch Process
        let process = Process()
        process.executableURL = xrayPath
        process.arguments = ["-config", configFile.path]
        
        // Capture stdout/stderr for debugging
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                // Log Xray core output to Apple System Log
                NSLog("[Xray Core]: %@", output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
        try process.run()
        self.xrayProcess = process
        
        NSLog("XrayProcessManager: Xray started with PID: %d", process.processIdentifier)
        
        // Short delay to ensure process initializes
        Thread.sleep(forTimeInterval: 0.5)
        
        // 6. Update State & System Proxy
        let currentApiPort = parseApiPort(config: modifiedConfig)
        self.apiPort = currentApiPort
        NSLog("XrayProcessManager: API port set to %d", currentApiPort)
        
        let currentSocksPort = parseSocksPort(config: modifiedConfig)
        self.socksPort = Int(currentSocksPort) ?? 10808
        NSLog("XrayProcessManager: SOCKS port set to %d", self.socksPort)
        
        setSystemProxy(config: modifiedConfig)
        startStatsMonitoring()
        
        return true
    }
    
    /// Stops the Xray process and cleans up resources.
    ///
    /// This method ensures a clean shutdown by:
    /// 1. Disabling the system proxy.
    /// 2. Stopping the stats timer.
    /// 3. Sending a termination signal to the process.
    /// 4. Force-killing the process if it refuses to exit.
    /// 5. Deleting the temporary configuration file.
    func stop() {
        // 1. Clean up System Proxy
        clearSystemProxy()
        
        // 2. Stop Monitoring
        statsTimer?.invalidate()
        statsTimer = nil

        // 3. Terminate Process
        if let process = xrayProcess, process.isRunning {
            process.terminate()

            // 4. Force Kill Fallback
            let group = DispatchGroup()
            group.enter()
            // Give it 2 seconds to exit gracefully
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                if process.isRunning {
                    let pid = process.processIdentifier
                    if pid > 0 {
                        NSLog("XrayProcessManager: Process unresponsive, force killing PID %d", pid)
                        _ = Darwin.kill(pid_t(pid), SIGKILL)
                    }
                }
                group.leave()
            }
            process.waitUntilExit()
            group.wait()
        }

        xrayProcess = nil

        // 5. Cleanup Files
        if let configPath = configPath {
            try? FileManager.default.removeItem(at: configPath)
            self.configPath = nil
        }

        // 6. Reset Stats
        totalUpload = 0
        totalDownload = 0
        uploadSpeed = 0
        downloadSpeed = 0
    }
    
    /// Returns `true` if the Xray process is currently running.
    var isRunning: Bool {
        return xrayProcess?.isRunning ?? false
    }
    
    /// Retrieves the version string from the Xray binary.
    ///
    /// Executes `xray version` and parses the output.
    func getVersion() -> String? {
        guard let xrayPath = findXrayExecutable() else { return nil }
        
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
                // Parse first line containing "Xray"
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
    
    /// Measures latency to a target URL.
    ///
    /// Performs an HTTP HEAD request to the specified URL.
    /// - If Xray is running, the request is routed through the local SOCKS5 proxy.
    /// - If Xray is not running, the request is sent directly.
    ///
    /// - Parameter url: The target URL string (e.g., "https://www.google.com").
    /// - Returns: The latency in milliseconds, or -1 if the request fails.
    func measureDelay(url: String) -> Int {
        guard let targetUrl = URL(string: url) else {
            NSLog("XrayProcessManager: Invalid URL for delay check: %@", url)
            return -1
        }
        
        var request = URLRequest(url: targetUrl)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 3.0
        
        // If Xray is running, route through the SOCKS5 proxy
        if isRunning {
            NSLog("XrayProcessManager: Measuring delay through SOCKS5 proxy at 127.0.0.1:%d to %@", socksPort, url)
            config.connectionProxyDictionary = [
                kCFStreamPropertySOCKSProxyHost: "127.0.0.1",
                kCFStreamPropertySOCKSProxyPort: socksPort,
                kCFStreamPropertySOCKSVersion: kCFStreamSocketSOCKSVersion5
            ]
        } else {
             NSLog("XrayProcessManager: Measuring direct delay to %@", url)
        }
        
        let session = URLSession(configuration: config)
        let group = DispatchGroup()
        var latency: Int = -1
        
        group.enter()
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let task = session.dataTask(with: request) { _, response, error in
            defer { group.leave() }
            
            if let error = error {
                NSLog("XrayProcessManager: Delay check failed: %@", error.localizedDescription)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                latency = Int(duration * 1000)
                // NSLog("XrayProcessManager: Delay success: %d ms (Status: %d)", latency, httpResponse.statusCode)
            }
        }
        
        task.resume()
        
        // Wait for max 3 seconds
        _ = group.wait(timeout: .now() + 3.0)
        
        return latency
    }
    
    /// Alias for `measureDelay`.
    func getConnectedServerDelay(url: String) -> Int {
        return measureDelay(url: url)
    }
    
    // MARK: - Private Helper Methods
    
    /// Detects available network services (e.g., "Wi-Fi", "Ethernet") using `networksetup`.
    ///
    /// This is crucial for correctly applying proxy settings to the active network interface.
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
        
        return ["Wi-Fi", "Ethernet"] // Fallback
    }

    /// Extracts the API port from the Xray configuration.
    ///
    /// Handles both integer ports and "IP:Port" string formats.
    private func parseApiPort(config: String) -> Int {
        guard let data = config.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let api = json["api"] as? [String: Any] else {
            return 10085 // Default Xray API port
        }
        
        if let port = api["port"] as? Int {
            return port
        }
        
        if let listen = api["listen"] as? String {
            // Handle "127.0.0.1:10085" format
            let components = listen.components(separatedBy: ":")
            if components.count == 2, let port = Int(components[1]) {
                return port
            }
        }
        
        return 10085
    }

    /// Extracts the SOCKS inbound port from the configuration.
    ///
    /// Looks for an inbound with tag "in_proxy" or protocol "socks".
    private func parseSocksPort(config: String) -> String {
        guard let data = config.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inbounds = json["inbounds"] as? [[String: Any]] else {
            return "10808" // Default SOCKS port
        }
        
        for inbound in inbounds {
            // Prioritize by tag
            if let tag = inbound["tag"] as? String, tag == "in_proxy",
               let port = inbound["port"] as? Int {
                return String(port)
            }
            // Fallback to protocol
            if let protocolName = inbound["protocol"] as? String, protocolName == "socks",
               let port = inbound["port"] as? Int {
                return String(port)
            }
        }
        
        return "10808"
    }

    /// Configures the macOS system proxy settings using `networksetup`.
    ///
    /// Sets the SOCKS proxy and bypass domains for all detected network services.
    private func setSystemProxy(config: String) {
        let services = getNetworkServices()
        let port = parseSocksPort(config: config)
        
        NSLog("XrayProcessManager: Setting system proxy to port %@", port)
        
        for service in services {
            // 1. Set SOCKS Proxy Host/Port
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            task.arguments = ["-setsocksfirewallproxy", service, "127.0.0.1", port]
            try? task.run()
            task.waitUntilExit()
            
            // 2. Enable SOCKS Proxy
            let enableTask = Process()
            enableTask.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            enableTask.arguments = ["-setsocksfirewallproxystate", service, "on"]
            try? enableTask.run()
            enableTask.waitUntilExit()
            
            // 3. Configure Bypass Domains (Localhost, LAN, etc.)
            let bypassTask = Process()
            bypassTask.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            bypassTask.arguments = ["-setproxybypassdomains", service, "localhost", "127.0.0.1", "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12"]
            try? bypassTask.run()
            bypassTask.waitUntilExit()
        }
        NSLog("XrayProcessManager: Attempted to set system proxy for: %@", services.joined(separator: ", "))
    }
    
    /// Disables the system proxy settings.
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
    
    // MARK: - Statistics Logic
    
    /// Starts the periodic timer to query traffic statistics.
    private func startStatsMonitoring() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    /// Queries the Xray API for current traffic statistics.
    ///
    /// Uses the `xray api statsquery` CLI command to retrieve JSON stats.
    /// Parses the JSON to calculate total upload and download usage.
    private func updateStats() {
        guard let xrayPath = findXrayExecutable() else {
            NSLog("XrayProcessManager: Cannot update stats - binary not found")
            return
        }
        
        // Execute: xray api statsquery --server=127.0.0.1:<port> ""
        let task = Process()
        task.executableURL = xrayPath
        // The empty string argument "" is a pattern to match ALL stats
        task.arguments = ["api", "statsquery", "--server=127.0.0.1:\(apiPort)", ""]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        let errorPipe = Pipe()
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            // Log errors if any
            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                NSLog("XrayProcessManager: Stats query error: %@", errorOutput)
            }
            
            guard let output = String(data: data, encoding: .utf8) else { return }
            
            // Parse JSON Output
            // Expected Format: { "stat": [ { "name": "...", "value": 123 }, ... ] }
            
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
                    
                    // Filter Logic:
                    // 1. We only care about "outbound" traffic to measure what's leaving the device.
                    // 2. We exclude "blackhole" (blocked) traffic.
                    // 3. We differentiate between "uplink" (upload) and "downlink" (download).
                    if name.hasPrefix("outbound>>>") && !name.contains("blackhole") {
                        if name.hasSuffix(">>>uplink") {
                            currentUpload += value
                        } else if name.hasSuffix(">>>downlink") {
                            currentDownload += value
                        }
                    }
                }
            }
            
            // Calculate Real-time Speed (Bytes/Second)
            // Speed = (Current Total - Last Total) / Time Interval (1s)
            if lastUpload > 0 || lastDownload > 0 {
                uploadSpeed = max(0, currentUpload - lastUpload)
                downloadSpeed = max(0, currentDownload - lastDownload)
            }
            
            // Update Published Properties
            totalUpload = currentUpload
            totalDownload = currentDownload
            
            // Update Snapshots for Next Cycle
            lastUpload = currentUpload
            lastDownload = currentDownload
            
        } catch {
            NSLog("Error querying stats: %@", error.localizedDescription)
        }
    }
}

// MARK: - Error Definitions

enum XrayError: LocalizedError {
    case executableNotFound
    case invalidConfig
    case processStartFailed
    case apiConnectionFailed
    
    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Xray executable not found. Please ensure the binary is placed in ~/.flutter_vless/xray"
        case .invalidConfig:
            return "Invalid Xray configuration JSON provided."
        case .processStartFailed:
            return "Failed to start the Xray process."
        case .apiConnectionFailed:
            return "Failed to connect to the Xray API."
        }
    }
}

