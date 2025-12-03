#ifndef VPN_SERVICE_H_
#define VPN_SERVICE_H_

#include <string>
#include <memory>
#include <atomic>
#include <thread>
#include <mutex>
#include <filesystem>
#include <optional>
#include <vector>

#include "proxy_service.h" // For ProcessHandle and helper functions

namespace fs = std::filesystem;

class VpnService {
 public:
  VpnService();
  ~VpnService();

  // Starts the VPN service (Xray + Tun2Socks)
  bool Start(const std::string& config);

  // Stops the VPN service
  void Stop();

  // Checks if the service is running
  bool IsRunning() const;

  // Stats
  void GetTrafficStats(int64_t& upload, int64_t& download);

 private:
  // Helper methods
  void RunVpn();
  bool StartXrayProcess(const std::string& config_path);
  bool StartTun2SocksProcess(uint16_t socks_port);
  void StopProcesses();
  
  // Stats helpers
  void UpdateTrafficStats();
  bool RunXrayApiCommand(const std::string& args, std::string& output);
  std::string InjectApiConfig(const std::string& config);
  
  // Configuration helpers
  bool WriteConfigToFile(const std::string& config, fs::path& config_path);
  std::optional<fs::path> FindTun2SocksExecutable();
  
  // Members
  std::atomic<bool> is_running_{false};
  std::thread vpn_thread_;
  std::thread stats_thread_;
  
  std::unique_ptr<ProcessHandle> xray_process_;
  std::unique_ptr<ProcessHandle> tun2socks_process_;
  
  fs::path xray_executable_path_;
  fs::path tun2socks_executable_path_;
  fs::path temp_config_path_;
  
  std::string current_config_;
  
  // Stats
  std::mutex stats_mutex_;
  int64_t total_upload_ = 0;
  int64_t total_download_ = 0;
  std::string api_address_ = "127.0.0.1:10086"; // Different port than ProxyService to avoid conflict? Or same?
  
  // We reuse ProxyService's helper for finding Xray and assets
  // or we can duplicate the logic if we want total decoupling.
  // For now, we'll implement our own finders to keep it self-contained
  // or use shared helpers if we refactor further. 
  // To avoid circular deps or complex refactoring now, we'll duplicate the simple find logic.
  std::optional<fs::path> FindXrayExecutable();
  std::optional<fs::path> FindXrayAssets(const fs::path& executable_path);
  
  // Routing helpers
  std::string ExtractServerAddress(const std::string& config);
  std::string ResolveToIP(const std::string& address);
  std::string GetDefaultGateway();
};

#endif // VPN_SERVICE_H_
