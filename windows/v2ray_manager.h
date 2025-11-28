#ifndef V2RAY_MANAGER_H_
#define V2RAY_MANAGER_H_

#include <string>
#include <memory>
#include <thread>
#include <atomic>
#include <mutex>
#include <optional>
#include <filesystem>
#include <chrono>
#include <future>
#include <map>
#include <cstdint>

namespace fs = std::filesystem;

// Forward declarations
struct ProcessHandle;
struct ApiClient;

/**
 * @brief Manages Xray-core process lifecycle and configuration on Windows.
 * 
 * @details Platform-Specific Implementation:
 * This class handles Xray process management with Windows-specific considerations:
 * 
 * - VPN Mode: Uses system proxy + Xray routing rules (TUN not supported on Windows)
 * - Proxy Mode: Uses system proxy only
 * - Process Management: Uses Windows CreateProcess API
 * - System Integration: Manages Windows system proxy via WinINET API
 * 
 * @details TUN Protocol Limitation:
 * Unlike Android/iOS which use TUN interfaces (VpnService/PacketTunnel), Windows
 * Xray does not support the TUN protocol. The standard Windows Xray build lacks
 * kernel-level network interface creation capabilities required for TUN.
 * 
 * Therefore, VPN mode on Windows is implemented using:
 * 1. System-wide SOCKS5 proxy configuration (via WinINET API)
 * 2. Xray routing rules to ensure all traffic goes through proxy outbound
 * 
 * This provides VPN-like functionality for most applications, though it's not
 * a true virtual network interface. Applications that bypass system proxy
 * settings may not be routed correctly.
 * 
 * @note The manager runs Xray in a separate thread and monitors its health.
 * @note Temporary configuration files are created in %TEMP%/flutter_vless/
 * @note System proxy is automatically cleared on Stop() to prevent persistence.
 */
class V2rayManager {
 public:
  /**
   * @brief Constructs a V2rayManager instance.
   * 
   * Searches for xray.exe in common locations:
   * - Current directory and subdirectories
   * - Application directory
   * - Common installation paths (AppData, Program Files)
   * 
   * @note If xray.exe is not found, Start() will fail with an error message.
   */
  V2rayManager();
  
  /**
   * @brief Destroys the V2rayManager instance.
   * 
   * Automatically stops Xray process and cleans up resources:
   * - Stops Xray process if running
   * - Clears system proxy if set
   * - Joins all worker threads
   * - Removes temporary configuration files
   */
  ~V2rayManager();

  // Non-copyable, movable
  V2rayManager(const V2rayManager&) = delete;
  V2rayManager& operator=(const V2rayManager&) = delete;
  V2rayManager(V2rayManager&&) = default;
  V2rayManager& operator=(V2rayManager&&) = default;

  bool Start(const std::string& config, bool proxy_only = false);
  void Stop();
  
  // Async delay measurement
  std::future<int> GetServerDelayAsync(const std::string& config, const std::string& url);
  int GetServerDelay(const std::string& config, const std::string& url);
  int GetConnectedServerDelay(const std::string& url);
  
  std::string GetCoreVersion();
  void GetTrafficStats(int64_t& upload, int64_t& download);

 private:
  friend struct ApiClient;
  void RunV2ray();
  bool StartXrayProcess(const std::string& config_path);
  void StopXrayProcess();
  bool WriteConfigToFile(const std::string& config, fs::path& config_path);
  
  // API communication
  bool InitializeApiClient();
  void UpdateTrafficStats();
  int MeasureDelayViaApi(const std::string& url);
  // Port helpers
  bool IsPortFree(uint16_t port);
  uint16_t FindFreePort();
  bool ReplacePortsInConfigFile(const fs::path& config_path);
  // Try to detect Xray API listen address ("address" + "port" or single "port")
  std::optional<std::string> DetectApiAddressInConfig(const fs::path& config_path);
  
  // Helper methods
  std::optional<fs::path> FindXrayExecutable();
  std::optional<fs::path> FindXrayAssets(const fs::path& executable_path);
  bool ValidateConfig(const std::string& config);
  void CleanupTempFiles();
  
  /**
   * @brief Modifies Xray configuration for Windows platform-specific requirements.
   * 
   * This function adapts the Xray configuration to work correctly on Windows.
   * 
   * @note TUN Protocol Limitation:
   * Xray on Windows does not support the TUN protocol (unlike Linux/Android/iOS).
   * The TUN protocol requires kernel-level network interface creation, which is
   * not available in standard Windows Xray builds. Attempting to use TUN on
   * Windows results in "unknown config id: tun" error.
   * 
   * @param proxy_only If true, returns the configuration unchanged (proxy mode).
   *                   If false, modifies routing for VPN mode.
   * 
   * @return Modified configuration string with Windows-specific settings.
   * 
   * @details VPN Mode Implementation:
   * For VPN mode on Windows, we use a hybrid approach:
   * 1. System Proxy: All applications route traffic through SOCKS5 proxy
   * 2. Xray Routing: Configure routing rules to ensure all traffic goes through
   *    the "proxy" outbound tag, providing consistent routing behavior.
   * 
   * This approach provides VPN-like functionality for most applications, though
   * it's not a true TUN interface. Some low-level network operations may bypass
   * the proxy, but the majority of user applications will respect system proxy
   * settings.
   * 
   * @details Routing Configuration:
   * The function adds or modifies the "routing" section to include a rule that
   * routes all TCP and UDP traffic through the outbound tagged as "proxy".
   * This ensures that even if an application bypasses system proxy, Xray will
   * still route the traffic correctly.
   * 
   * @warning The configuration must contain an outbound with tag "proxy" for
   *          VPN mode to work correctly.
   */
  std::string ModifyConfigForWindows(const std::string& config, bool proxy_only);
  
  /**
   * @brief Configures Windows system-wide proxy settings using WinINET API.
   * 
   * Sets the system proxy to route all network traffic through the specified
   * SOCKS5 proxy server. This affects all applications that respect Windows
   * system proxy settings.
   * 
   * @param proxy_address The proxy server address (typically "127.0.0.1").
   * @param proxy_port The SOCKS5 proxy port (typically 10807).
   * 
   * @return true if proxy was set successfully, false otherwise.
   * 
   * @details Implementation:
   * Uses INTERNET_PER_CONN_OPTION_LISTW with Unicode WinINET API:
   * - Sets PROXY_TYPE_PROXY flag to enable proxy
   * - Configures proxy server as "socks=127.0.0.1:PORT"
   * - Sets bypass list for local addresses (localhost, private networks)
   * - Notifies system of changes via INTERNET_OPTION_SETTINGS_CHANGED
   * 
   * @note The proxy string format is "socks=ADDRESS:PORT" which Windows
   *       interprets as SOCKS5 protocol.
   * 
   * @note Bypass list includes:
   * - localhost
   * - 127.* (loopback addresses)
   * - 10.*, 172.16-31.*, 192.168.* (private networks)
   * 
   * This prevents proxy loops and ensures local services remain accessible.
   * 
   * @warning Requires appropriate permissions. May fail if user lacks
   *          administrative privileges or if WinINET API is unavailable.
   */
  bool SetSystemProxy(const std::string& proxy_address, uint16_t proxy_port);
  
  /**
   * @brief Clears Windows system-wide proxy settings.
   * 
   * Removes the system proxy configuration, restoring direct network access.
   * This should be called when stopping the VPN/proxy service to restore
   * normal network behavior.
   * 
   * @return true if proxy was cleared successfully, false otherwise.
   * 
   * @details Implementation:
   * Sets PROXY_TYPE_DIRECT flag to disable proxy and restore direct connections.
   * Notifies the system of changes to ensure all applications pick up the
   * new settings immediately.
   * 
   * @note This function should always be called during cleanup to prevent
   *       leaving the system in a proxied state after application termination.
   */
  bool ClearSystemProxy();

  // Thread synchronization and state
  std::atomic<bool> is_running_{false};  ///< Flag indicating if Xray is running
  std::thread v2ray_thread_;              ///< Thread running Xray process management
  std::thread stats_thread_;              ///< Thread updating traffic statistics
  std::string current_config_;            ///< Current Xray configuration JSON
  bool proxy_only_ = false;              ///< If true, proxy mode; if false, VPN mode
  
  // Traffic statistics (protected by stats_mutex_)
  std::mutex stats_mutex_;                ///< Mutex protecting traffic statistics
  int64_t total_upload_ = 0;              ///< Total bytes uploaded (cumulative)
  int64_t total_download_ = 0;            ///< Total bytes downloaded (cumulative)
  int64_t upload_speed_ = 0;              ///< Current upload speed (bytes/second)
  int64_t download_speed_ = 0;            ///< Current download speed (bytes/second)
  
  // Process management
  std::unique_ptr<ProcessHandle> xray_process_;  ///< Handle to Xray process
  std::unique_ptr<ApiClient> api_client_;       ///< Client for Xray API communication
  
  // Configuration and paths
  fs::path temp_config_path_;             ///< Path to temporary Xray config file
  fs::path xray_executable_path_;         ///< Path to xray.exe executable
  std::string api_address_ = "127.0.0.1:10085";  ///< Xray API address (host:port)
  std::chrono::steady_clock::time_point start_time_;  ///< When Xray was started
  
  // Proxy settings buffers (must persist during WinINET API calls)
  std::vector<char> proxy_server_buf_;   ///< Buffer for proxy server string (Unicode)
  std::vector<char> proxy_bypass_buf_;    ///< Buffer for proxy bypass list (Unicode)
};

// Process handle wrapper for xray.exe
// The concrete Windows HANDLE/PROCESS_INFORMATION usage is implemented
// in the .cpp file to avoid pulling <windows.h> (and transitively
// winsock headers) into public headers which breaks include ordering
// in some translation units.
struct ProcessHandle {
  // Opaque handles stored as integer-sized values to avoid windows types
  std::uintptr_t hProcess = 0;
  std::uintptr_t hThread = 0;
  // Pipe handles for capturing stdout/stderr of the child process.
  std::uintptr_t hStdOutRead = 0;
  std::uintptr_t hStdErrRead = 0;

  ProcessHandle();
  ~ProcessHandle();

  // Close the process and handles. Implemented in .cpp.
  void Close();

  // Query whether the child process is still running.
  bool IsRunning() const;
};

/**
 * @brief Client for communicating with Xray API.
 * 
 * @details API Protocol:
 * Xray API uses gRPC protocol, not HTTP/REST. However, for simplicity,
 * this implementation uses HTTP requests to query statistics endpoints.
 * 
 * @details API Endpoints:
 * - /stats: Returns traffic statistics in JSON format
 * - /api/v1/version: Returns Xray version information
 * 
 * @note The API must be enabled in Xray configuration for these methods to work.
 * @note Default API address is 127.0.0.1:10085.
 */
struct ApiClient {
  std::string api_address_;  ///< API server address (host:port format)
  int api_port_ = 10085;     ///< API server port (default: 10085)
  
  /**
   * @brief Retrieves traffic statistics from Xray API via CLI.
   * 
   * @param stats Output map of statistic names to values.
   * 
   * @return true if statistics were retrieved successfully, false otherwise.
   * 
   * @details Implementation:
   * Executes `xray.exe api statsquery` to get all statistics.
   * Parses the output line by line.
   */
  bool GetStats(std::map<std::string, int64_t>& stats);
  
  /**
   * @brief Measures network delay through Xray proxy.
   * 
   * @param url URL to test (typically a simple HTTP endpoint like google.com).
   * 
   * @return Delay in milliseconds, or -1 on error.
   */
  int MeasureDelay(const std::string& url);
  
  /**
   * @brief Retrieves Xray core version from API.
   * 
   * @return Version string (e.g., "25.10.15") or empty string on error.
   */
  std::string GetVersion();
  
 private:
  /**
   * @brief Executes an Xray API command via CLI.
   * 
   * @param args Command line arguments (e.g., "api statsquery ...").
   * @param output Output string to store the command result.
   * 
   * @return true if command executed successfully, false otherwise.
   */
  bool RunXrayApiCommand(const std::string& args, std::string& output);
  
  // Reference to the manager to access executable path
  V2rayManager* manager_ = nullptr;
  
  friend class V2rayManager;
};

#endif  // V2RAY_MANAGER_H_
