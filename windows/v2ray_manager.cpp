#include "v2ray_manager.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <chrono>
#include <windows.h>
#include <wininet.h>
#include <process.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <algorithm>
#include <regex>
#include <map>
#include <vector>

#pragma comment(lib, "wininet.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "version.lib")

// JSON parsing helpers (simple implementation, can be replaced with nlohmann/json)
namespace json_utils {
  bool IsValidJson(const std::string& json_str) {
    // Basic JSON validation - check for balanced braces and brackets
    int brace_count = 0;
    int bracket_count = 0;
    bool in_string = false;
    bool escaped = false;
    
    for (char c : json_str) {
      if (escaped) {
        escaped = false;
        continue;
      }
      
      if (c == '\\') {
        escaped = true;
        continue;
      }
      
      if (c == '"') {
        in_string = !in_string;
        continue;
      }
      
      if (in_string) continue;
      
      if (c == '{') brace_count++;
      else if (c == '}') brace_count--;
      else if (c == '[') bracket_count++;
      else if (c == ']') bracket_count--;
      
      if (brace_count < 0 || bracket_count < 0) return false;
    }
    
    return brace_count == 0 && bracket_count == 0 && !in_string;
  }
  
  std::string ExtractStringValue(const std::string& json, const std::string& key) {
    std::regex pattern("\"" + key + "\"\\s*:\\s*\"([^\"]+)\"");
    std::smatch match;
    if (std::regex_search(json, match, pattern)) {
      return match[1].str();
    }
    return "";
  }
}

V2rayManager::V2rayManager() {
  xray_executable_path_ = FindXrayExecutable().value_or(fs::path());
}

V2rayManager::~V2rayManager() {
  Stop();
  CleanupTempFiles();
}

bool V2rayManager::Start(const std::string& config, bool proxy_only) {
  if (is_running_.load()) {
    Stop();
  }

  if (!ValidateConfig(config)) {
    std::cerr << "Invalid Xray configuration JSON" << std::endl;
    return false;
  }

  current_config_ = config;
  proxy_only_ = proxy_only;
  
  if (xray_executable_path_.empty()) {
    std::cerr << "Xray executable not found. Please ensure xray.exe is available." << std::endl;
    return false;
  }
  
  is_running_.store(true);
  v2ray_thread_ = std::thread(&V2rayManager::RunV2ray, this);
  
  return true;
}

void V2rayManager::Stop() {
  if (!is_running_.load()) {
    return;
  }

  is_running_.store(false);
  
  StopXrayProcess();
  
  if (v2ray_thread_.joinable()) {
    v2ray_thread_.join();
  }
  
  if (stats_thread_.joinable()) {
    stats_thread_.join();
  }

  // Reset stats
  std::lock_guard<std::mutex> lock(stats_mutex_);
  total_upload_ = 0;
  total_download_ = 0;
  upload_speed_ = 0;
  download_speed_ = 0;
}

void V2rayManager::RunV2ray() {
  // Write config to temporary file
  fs::path config_path;
  if (!WriteConfigToFile(current_config_, config_path)) {
    std::cerr << "Failed to write Xray configuration file" << std::endl;
    is_running_.store(false);
    return;
  }
  
  temp_config_path_ = config_path;
  
  // Start Xray process
  if (!StartXrayProcess(config_path.string())) {
    std::cerr << "Failed to start Xray process" << std::endl;
    is_running_.store(false);
    CleanupTempFiles();
    return;
  }
  
  // Wait a bit for Xray to start
  std::this_thread::sleep_for(std::chrono::milliseconds(500));
  
  // Initialize API client
  if (!InitializeApiClient()) {
    std::cerr << "Warning: Failed to initialize Xray API client. Stats may not be available." << std::endl;
  }
  
  start_time_ = std::chrono::steady_clock::now();
  
  // Start stats update thread
  stats_thread_ = std::thread([this]() {
    while (is_running_.load()) {
      UpdateTrafficStats();
      std::this_thread::sleep_for(std::chrono::seconds(1));
    }
  });
  
  // Monitor process
  while (is_running_.load()) {
    if (xray_process_ && !xray_process_->IsRunning()) {
      std::cerr << "Xray process terminated unexpectedly" << std::endl;
      is_running_.store(false);
      break;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
  }
  
  StopXrayProcess();
  CleanupTempFiles();
}

bool V2rayManager::StartXrayProcess(const std::string& config_path) {
  if (xray_executable_path_.empty() || !fs::exists(xray_executable_path_)) {
    return false;
  }
  
  xray_process_ = std::make_unique<ProcessHandle>();
  
  STARTUPINFOA si = {};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  
  // Create pipes for stdout/stderr if needed
  HANDLE hStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
  HANDLE hStdErr = GetStdHandle(STD_ERROR_HANDLE);
  si.hStdOutput = hStdOut;
  si.hStdError = hStdErr;
  si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  
  std::string command_line = "\"" + xray_executable_path_.string() + "\" -config \"" + config_path + "\"";
  std::vector<char> cmd_buffer(command_line.begin(), command_line.end());
  cmd_buffer.push_back('\0');
  
  BOOL success = CreateProcessA(
    nullptr,
    cmd_buffer.data(),
    nullptr,
    nullptr,
    TRUE,
    CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP,
    nullptr,
    xray_executable_path_.parent_path().string().c_str(),
    &si,
    &xray_process_->pi
  );
  
  if (!success) {
    DWORD error = GetLastError();
    std::cerr << "Failed to start Xray process. Error: " << error << std::endl;
    xray_process_.reset();
    return false;
  }
  
  return true;
}

void V2rayManager::StopXrayProcess() {
  if (xray_process_) {
    xray_process_->Close();
    xray_process_.reset();
  }
  api_client_.reset();
}

bool V2rayManager::WriteConfigToFile(const std::string& config, fs::path& config_path) {
  try {
    // Create temp directory if it doesn't exist
    fs::path temp_dir = fs::temp_directory_path() / "flutter_vless";
    fs::create_directories(temp_dir);
    
    // Generate unique filename
    auto now = std::chrono::system_clock::now();
    auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
      now.time_since_epoch()).count();
    
    config_path = temp_dir / ("xray_config_" + std::to_string(timestamp) + ".json");
    
    // Write config to file
    std::ofstream file(config_path, std::ios::binary);
    if (!file.is_open()) {
      return false;
    }
    
    file << config;
    file.close();
    
    return true;
  } catch (const std::exception& e) {
    std::cerr << "Error writing config file: " << e.what() << std::endl;
    return false;
  }
}

bool V2rayManager::InitializeApiClient() {
  api_client_ = std::make_unique<ApiClient>();
  api_client_->api_address_ = api_address_;
  
  // Test API connection
  std::string version = api_client_->GetVersion();
  return !version.empty();
}

void V2rayManager::UpdateTrafficStats() {
  if (!api_client_) {
    return;
  }
  
  std::map<std::string, int64_t> stats;
  if (!api_client_->GetStats(stats)) {
    return;
  }
  
  std::lock_guard<std::mutex> lock(stats_mutex_);
  
  // Update traffic stats from Xray API
  // Xray stats format: "inbound>>>tag>>>traffic>>>uplink" and "inbound>>>tag>>>traffic>>>downlink"
  int64_t new_upload = 0;
  int64_t new_download = 0;
  
  for (const auto& [key, value] : stats) {
    if (key.find("uplink") != std::string::npos) {
      new_upload += value;
    } else if (key.find("downlink") != std::string::npos) {
      new_download += value;
    }
  }
  
  upload_speed_ = new_upload - total_upload_;
  download_speed_ = new_download - total_download_;
  total_upload_ = new_upload;
  total_download_ = new_download;
}

int V2rayManager::MeasureDelayViaApi(const std::string& url) {
  if (!api_client_) {
    return -1;
  }
  return api_client_->MeasureDelay(url);
}

std::optional<fs::path> V2rayManager::FindXrayExecutable() {
  // Try multiple locations
  std::vector<fs::path> search_paths = {
    // Current directory
    fs::current_path() / "xray.exe",
    fs::current_path() / "xray" / "xray.exe",
    // Example app location (for development)
    fs::current_path() / "windows" / "xray" / "xray.exe",
    fs::current_path() / "example" / "windows" / "xray" / "xray.exe",
    // Parent directories
    fs::current_path().parent_path() / "xray.exe",
    fs::current_path().parent_path() / "xray" / "xray.exe",
    fs::current_path().parent_path() / "windows" / "xray" / "xray.exe",
    // Common installation locations
  };
  
  // Also check common installation locations
  char appdata_path[MAX_PATH];
  if (SHGetFolderPathA(nullptr, CSIDL_APPDATA, nullptr, SHGFP_TYPE_CURRENT, appdata_path) == S_OK) {
    search_paths.push_back(fs::path(appdata_path) / "flutter_vless" / "xray.exe");
  }
  
  char program_files[MAX_PATH];
  if (SHGetFolderPathA(nullptr, CSIDL_PROGRAM_FILES, nullptr, SHGFP_TYPE_CURRENT, program_files) == S_OK) {
    search_paths.push_back(fs::path(program_files) / "Xray" / "xray.exe");
  }
  
  // Check executable directory (where the app is running from)
  char exe_path[MAX_PATH];
  if (GetModuleFileNameA(nullptr, exe_path, MAX_PATH) > 0) {
    fs::path exe_dir = fs::path(exe_path).parent_path();
    search_paths.push_back(exe_dir / "xray.exe");
    search_paths.push_back(exe_dir / "xray" / "xray.exe");
  }
  
  for (const auto& path : search_paths) {
    if (fs::exists(path) && fs::is_regular_file(path)) {
      return path;
    }
  }
  
  return std::nullopt;
}

bool V2rayManager::ValidateConfig(const std::string& config) {
  return json_utils::IsValidJson(config);
}

void V2rayManager::CleanupTempFiles() {
  try {
    if (!temp_config_path_.empty() && fs::exists(temp_config_path_)) {
      fs::remove(temp_config_path_);
    }
  } catch (const std::exception& e) {
    std::cerr << "Error cleaning up temp files: " << e.what() << std::endl;
  }
}

std::future<int> V2rayManager::GetServerDelayAsync(const std::string& config, const std::string& url) {
  return std::async(std::launch::async, [this, config, url]() {
    return GetServerDelay(config, url);
  });
}

int V2rayManager::GetServerDelay(const std::string& config, const std::string& url) {
  // Create a temporary Xray instance to measure delay
  // This is a simplified implementation - in production, you might want to
  // use a more efficient approach
  
  if (!ValidateConfig(config)) {
    return -1;
  }
  
  // Write temp config
  fs::path temp_config;
  if (!WriteConfigToFile(config, temp_config)) {
    return -1;
  }
  
  // Start temporary Xray process
  auto temp_process = std::make_unique<ProcessHandle>();
  STARTUPINFOA si = {};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;
  
  std::string command_line = "\"" + xray_executable_path_.string() + "\" -config \"" + temp_config.string() + "\"";
  
  PROCESS_INFORMATION pi = {};
  BOOL success = CreateProcessA(
    nullptr,
    const_cast<char*>(command_line.c_str()),
    nullptr,
    nullptr,
    FALSE,
    CREATE_NO_WINDOW,
    nullptr,
    nullptr,
    &si,
    &pi
  );
  
  if (!success) {
    fs::remove(temp_config);
    return -1;
  }
  
  temp_process->pi = pi;
  
  // Wait for Xray to start
  std::this_thread::sleep_for(std::chrono::milliseconds(1000));
  
  // Create temporary API client
  auto temp_api = std::make_unique<ApiClient>();
  temp_api->api_address_ = api_address_;
  
  // Measure delay
  auto start = std::chrono::steady_clock::now();
  int delay = temp_api->MeasureDelay(url);
  auto end = std::chrono::steady_clock::now();
  
  // Cleanup
  temp_process->Close();
  fs::remove(temp_config);
  
  if (delay < 0) {
    return -1;
  }
  
  // Add overhead time
  auto overhead_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
  return delay + static_cast<int>(overhead_ms);
}

int V2rayManager::GetConnectedServerDelay(const std::string& url) {
  if (!is_running_.load() || !api_client_) {
    return -1;
  }
  return api_client_->MeasureDelay(url);
}

std::string V2rayManager::GetCoreVersion() {
  // Try to get version from API first
  if (api_client_) {
    std::string version = api_client_->GetVersion();
    if (!version.empty()) {
      return version;
    }
  }
  
  // Fallback: try to get version from executable file info
  if (!xray_executable_path_.empty() && fs::exists(xray_executable_path_)) {
    DWORD dummy;
    DWORD size = GetFileVersionInfoSizeA(xray_executable_path_.string().c_str(), &dummy);
    if (size > 0) {
      std::vector<char> buffer(size);
      if (GetFileVersionInfoA(xray_executable_path_.string().c_str(), 0, size, buffer.data())) {
        VS_FIXEDFILEINFO* file_info = nullptr;
        UINT len = 0;
        if (VerQueryValueA(buffer.data(), "\\", reinterpret_cast<LPVOID*>(&file_info), &len)) {
          if (file_info) {
            int major = HIWORD(file_info->dwFileVersionMS);
            int minor = LOWORD(file_info->dwFileVersionMS);
            int build = HIWORD(file_info->dwFileVersionLS);
            int revision = LOWORD(file_info->dwFileVersionLS);
            return std::to_string(major) + "." + 
                   std::to_string(minor) + "." + 
                   std::to_string(build) + "." + 
                   std::to_string(revision);
          }
        }
      }
    }
  }
  
  return "Unknown";
}

void V2rayManager::GetTrafficStats(int64_t& upload, int64_t& download) {
  std::lock_guard<std::mutex> lock(stats_mutex_);
  upload = total_upload_;
  download = total_download_;
}

// ApiClient implementation
bool ApiClient::GetStats(std::map<std::string, int64_t>& stats) {
  std::string response;
  if (!MakeApiRequest("/stats", response)) {
    return false;
  }
  
  // Parse JSON response
  // Xray stats API returns: {"stat":{"name":"value",...}}
  // Simple parsing - in production, use a proper JSON library
  std::regex stat_pattern("\"([^\"]+)\"\\s*:\\s*(\\d+)");
  std::sregex_iterator iter(response.begin(), response.end(), stat_pattern);
  std::sregex_iterator end;
  
  for (; iter != end; ++iter) {
    std::smatch match = *iter;
    std::string name = match[1].str();
    int64_t value = std::stoll(match[2].str());
    stats[name] = value;
  }
  
  return true;
}

int ApiClient::MeasureDelay(const std::string& url) {
  // Use Xray's outbound delay measurement
  // This requires making an HTTP request through Xray and measuring time
  HINTERNET hInternet = InternetOpenA("Xray-Delay-Test", INTERNET_OPEN_TYPE_DIRECT, nullptr, nullptr, 0);
  if (!hInternet) {
    return -1;
  }
  
  // Set timeout
  DWORD timeout = 5000; // 5 seconds
  InternetSetOptionA(hInternet, INTERNET_OPTION_CONNECT_TIMEOUT, &timeout, sizeof(timeout));
  InternetSetOptionA(hInternet, INTERNET_OPTION_RECEIVE_TIMEOUT, &timeout, sizeof(timeout));
  
  // Parse URL to get host and path
  std::string test_url = url.empty() ? "https://www.google.com/generate_204" : url;
  
  HINTERNET hConnect = InternetOpenUrlA(hInternet, test_url.c_str(), nullptr, 0, 
                                         INTERNET_FLAG_NO_CACHE_WRITE | INTERNET_FLAG_RELOAD, 0);
  if (!hConnect) {
    InternetCloseHandle(hInternet);
    return -1;
  }
  
  auto start = std::chrono::steady_clock::now();
  
  char buffer[1024];
  DWORD bytes_read = 0;
  BOOL result = InternetReadFile(hConnect, buffer, sizeof(buffer) - 1, &bytes_read);
  
  auto end = std::chrono::steady_clock::now();
  auto delay_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
  
  InternetCloseHandle(hConnect);
  InternetCloseHandle(hInternet);
  
  if (!result && GetLastError() != ERROR_SUCCESS) {
    return -1;
  }
  
  return static_cast<int>(delay_ms);
}

std::string ApiClient::GetVersion() {
  std::string response;
  if (MakeApiRequest("/api/v1/version", response)) {
    // Parse version from response
    std::regex version_pattern("\"version\"\\s*:\\s*\"([^\"]+)\"");
    std::smatch match;
    if (std::regex_search(response, match, version_pattern)) {
      return match[1].str();
    }
  }
  return "";
}

bool ApiClient::MakeApiRequest(const std::string& endpoint, std::string& response) {
  std::string url = BuildApiUrl(endpoint);
  
  HINTERNET hInternet = InternetOpenA("Xray-API-Client", INTERNET_OPEN_TYPE_DIRECT, nullptr, nullptr, 0);
  if (!hInternet) {
    return false;
  }
  
  HINTERNET hConnect = InternetOpenUrlA(hInternet, url.c_str(), nullptr, 0, 
                                       INTERNET_FLAG_NO_CACHE_WRITE | INTERNET_FLAG_RELOAD, 0);
  if (!hConnect) {
    InternetCloseHandle(hInternet);
    return false;
  }
  
  char buffer[4096];
  DWORD bytes_read = 0;
  response.clear();
  
  while (InternetReadFile(hConnect, buffer, sizeof(buffer) - 1, &bytes_read) && bytes_read > 0) {
    buffer[bytes_read] = '\0';
    response += buffer;
  }
  
  InternetCloseHandle(hConnect);
  InternetCloseHandle(hInternet);
  
  return !response.empty();
}

std::string ApiClient::BuildApiUrl(const std::string& endpoint) {
  return "http://" + api_address_ + endpoint;
}
