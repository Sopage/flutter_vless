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

class V2rayManager {
 public:
  V2rayManager();
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
  bool ValidateConfig(const std::string& config);
  void CleanupTempFiles();
  
  // Configuration modification for Windows
  std::string ModifyConfigForWindows(const std::string& config, bool proxy_only);
  
  // Windows system proxy management
  bool SetSystemProxy(const std::string& proxy_address, uint16_t proxy_port);
  bool ClearSystemProxy();

  std::atomic<bool> is_running_{false};
  std::thread v2ray_thread_;
  std::thread stats_thread_;
  std::string current_config_;
  bool proxy_only_ = false;
  
  std::mutex stats_mutex_;
  int64_t total_upload_ = 0;
  int64_t total_download_ = 0;
  int64_t upload_speed_ = 0;
  int64_t download_speed_ = 0;
  
  // Process management
  std::unique_ptr<ProcessHandle> xray_process_;
  std::unique_ptr<ApiClient> api_client_;
  
  // Configuration
  fs::path temp_config_path_;
  fs::path xray_executable_path_;
  std::string api_address_ = "127.0.0.1:10085";  // Default Xray API address
  std::chrono::steady_clock::time_point start_time_;
  
  // Proxy settings buffers (must persist during API calls)
  std::vector<char> proxy_server_buf_;
  std::vector<char> proxy_bypass_buf_;
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

// API client for Xray stats and delay measurement
struct ApiClient {
  std::string api_address_;
  int api_port_ = 10085;
  
  // Get traffic statistics from Xray API
  bool GetStats(std::map<std::string, int64_t>& stats);
  
  // Measure delay through Xray
  int MeasureDelay(const std::string& url);
  
  // Get Xray version
  std::string GetVersion();
  
 private:
  bool MakeApiRequest(const std::string& endpoint, std::string& response);
  std::string BuildApiUrl(const std::string& endpoint);
};

#endif  // V2RAY_MANAGER_H_
