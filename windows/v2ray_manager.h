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
  
  // Helper methods
  std::optional<fs::path> FindXrayExecutable();
  bool ValidateConfig(const std::string& config);
  void CleanupTempFiles();

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
};

// Process handle wrapper for xray.exe
struct ProcessHandle {
  HANDLE hProcess = INVALID_HANDLE_VALUE;
  HANDLE hThread = INVALID_HANDLE_VALUE;
  PROCESS_INFORMATION pi = {};
  
  ~ProcessHandle() {
    Close();
  }
  
  void Close() {
    if (pi.hProcess != INVALID_HANDLE_VALUE) {
      TerminateProcess(pi.hProcess, 0);
      CloseHandle(pi.hProcess);
      CloseHandle(pi.hThread);
      pi.hProcess = INVALID_HANDLE_VALUE;
      pi.hThread = INVALID_HANDLE_VALUE;
    }
  }
  
  bool IsRunning() const {
    if (pi.hProcess == INVALID_HANDLE_VALUE) return false;
    DWORD exit_code;
    if (GetExitCodeProcess(pi.hProcess, &exit_code)) {
      return exit_code == STILL_ACTIVE;
    }
    return false;
  }
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
