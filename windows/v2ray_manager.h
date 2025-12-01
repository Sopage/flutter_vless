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

#include "proxy_service.h"

namespace fs = std::filesystem;

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
  void RunV2ray(); // Kept for VPN stub
  
  // Helper methods
  bool ValidateConfig(const std::string& config);
  
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
  
  // Thread synchronization and state
  std::atomic<bool> is_running_{false};  ///< Flag indicating if Xray is running
  std::thread v2ray_thread_;              ///< Thread running Xray process management (for VPN stub)
  std::string current_config_;            ///< Current Xray configuration JSON
  bool proxy_only_ = false;              ///< If true, proxy mode; if false, VPN mode
  
  // Proxy Service Delegate
  std::unique_ptr<ProxyService> proxy_service_;
};

#endif  // V2RAY_MANAGER_H_
