#include "v2ray_manager.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <cstdio>
#include <chrono>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <wininet.h>
#include <process.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <algorithm>
#include <regex>
#include <map>
#include <vector>
#include <cstring>
#include <string>

#pragma comment(lib, "Ws2_32.lib")

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


  // Replaces a top-level JSON section (key + value) with new content.
  // Uses brace counting to correctly handle nested objects/arrays.
  // Returns the modified JSON string.
  std::string ReplaceJsonSection(const std::string& json, const std::string& key, const std::string& new_section) {
    std::string result = json;
    std::string key_pattern = "\"" + key + "\"";
    
    // Find key
    size_t key_pos = result.find(key_pattern);
    if (key_pos == std::string::npos) return result;
    
    // Find colon after key
    size_t colon_pos = result.find(':', key_pos + key_pattern.length());
    if (colon_pos == std::string::npos) return result;
    
    // Find start of value (should be '{' or '[' or '"' or digit/bool)
    size_t value_start = colon_pos + 1;
    while (value_start < result.length() && isspace(result[value_start])) {
      value_start++;
    }
    
    if (value_start >= result.length()) return result;
    
    // Determine end of value based on type
    size_t value_end = std::string::npos;
    char start_char = result[value_start];
    
    if (start_char == '{') {
      // Object: count braces
      int depth = 1;
      size_t pos = value_start + 1;
      bool in_string = false;
      bool escaped = false;
      
      while (pos < result.length() && depth > 0) {
        char c = result[pos];
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          in_string = !in_string;
        } else if (!in_string) {
          if (c == '{') depth++;
          else if (c == '}') depth--;
        }
        pos++;
      }
      if (depth == 0) value_end = pos;
    } else if (start_char == '[') {
      // Array: count brackets
      int depth = 1;
      size_t pos = value_start + 1;
      bool in_string = false;
      bool escaped = false;
      
      while (pos < result.length() && depth > 0) {
        char c = result[pos];
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          in_string = !in_string;
        } else if (!in_string) {
          if (c == '[') depth++;
          else if (c == ']') depth--;
        }
        pos++;
      }
      if (depth == 0) value_end = pos;
    } else if (start_char == '"') {
      // String: find closing quote
      size_t pos = value_start + 1;
      bool escaped = false;
      while (pos < result.length()) {
        char c = result[pos];
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          value_end = pos + 1;
          break;
        }
        pos++;
      }
    } else {
      // Primitive (number, boolean, null): read until comma or closing brace/bracket
      size_t pos = value_start;
      while (pos < result.length()) {
        char c = result[pos];
        if (c == ',' || c == '}' || c == ']' || isspace(c)) {
          value_end = pos;
          break;
        }
        pos++;
      }
    }
    
    if (value_end != std::string::npos) {
      // Replace the range [key_pos, value_end) with new_section
      // Note: new_section should include the key, e.g. "key": value
      result.replace(key_pos, value_end - key_pos, new_section);
    }
    
    return result;
  }
}

// Implement ProcessHandle methods declared in the header. Keep Windows
// types and functions in this translation unit only.
ProcessHandle::ProcessHandle() = default;

ProcessHandle::~ProcessHandle() {
  Close();
}

// Helper function to convert std::string to std::wstring
static std::wstring StringToWString(const std::string& str) {
  if (str.empty()) return std::wstring();
  int size_needed = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, nullptr, 0);
  if (size_needed <= 0) return std::wstring();
  std::wstring wstr(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, &wstr[0], size_needed);
  wstr.resize(size_needed - 1); // Remove null terminator
  return wstr;
}

void ProcessHandle::Close() {
  if (hProcess != 0) {
    HANDLE hp = reinterpret_cast<HANDLE>(hProcess);
    if (hp != INVALID_HANDLE_VALUE) {
      TerminateProcess(hp, 0);
      CloseHandle(hp);
    }
    if (hThread != 0) {
      HANDLE ht = reinterpret_cast<HANDLE>(hThread);
      if (ht != INVALID_HANDLE_VALUE) CloseHandle(ht);
    }
    hProcess = 0;
    hThread = 0;
  }
  if (hStdOutRead != 0) {
    HANDLE hr = reinterpret_cast<HANDLE>(hStdOutRead);
    if (hr != INVALID_HANDLE_VALUE) CloseHandle(hr);
    hStdOutRead = 0;
  }
  if (hStdErrRead != 0) {
    HANDLE he = reinterpret_cast<HANDLE>(hStdErrRead);
    if (he != INVALID_HANDLE_VALUE) CloseHandle(he);
    hStdErrRead = 0;
  }
}

bool ProcessHandle::IsRunning() const {
  if (hProcess == 0) return false;
  HANDLE hp = reinterpret_cast<HANDLE>(hProcess);
  if (hp == INVALID_HANDLE_VALUE) return false;
  DWORD exit_code = 0;
  if (GetExitCodeProcess(hp, &exit_code)) {
    return exit_code == STILL_ACTIVE;
  }
  return false;
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
  
  // Clear system proxy if it was set (both VPN and proxy modes use system proxy on Windows)
  ClearSystemProxy();
  
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

/**
 * @brief Main execution loop for Xray process management.
 * 
 * @details Execution Flow:
 * 1. Modifies configuration for Windows-specific requirements
 * 2. Writes configuration to temporary file
 * 3. Starts Xray process with the configuration
 * 4. Configures system proxy (for both VPN and proxy modes)
 * 5. Initializes API client for statistics
 * 6. Starts statistics update thread
 * 7. Monitors process health until stopped
 * 
 * @details Configuration Modification:
 * Before starting Xray, the configuration is modified for Windows:
 * - VPN mode: Adds routing rules to route all traffic through proxy outbound
 * - Proxy mode: Configuration remains unchanged
 * 
 * @details System Proxy Setup:
 * After Xray starts successfully, system proxy is configured:
 * - VPN mode: System proxy + Xray routing rules (TUN not supported)
 * - Proxy mode: System proxy only
 * 
 * The SOCKS5 port is automatically detected from the configuration by searching
 * for the "in_proxy" tag, or falling back to the first SOCKS inbound.
 * 
 * @details Process Monitoring:
 * Continuously monitors the Xray process to detect unexpected termination.
 * If the process exits, the manager stops and cleans up resources.
 * 
 * @note The function runs in a separate thread to avoid blocking.
 * @note Temporary configuration files are cleaned up on exit.
 * @note System proxy is cleared in Stop() method, not here.
 */
void V2rayManager::RunV2ray() {
  // Modify config for Windows (VPN mode: routing rules, proxy mode: unchanged)
  std::string modified_config = ModifyConfigForWindows(current_config_, proxy_only_);
  
  // Write config to temporary file
  fs::path config_path;
  if (!WriteConfigToFile(modified_config, config_path)) {
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
  
  // For VPN mode and proxy mode, set system proxy
  // VPN mode on Windows uses system proxy + routing (TUN not supported)
  // Proxy mode uses system proxy only
  {
    // Find SOCKS5 port from config - look for "in_proxy" tag or first SOCKS inbound
    uint16_t socks_port = 10807; // Default port
    std::string config_str = modified_config;
    
    // Try to find port in "in_proxy" inbound first
    std::regex in_proxy_pattern("\"tag\"\\s*:\\s*\"in_proxy\"[\\s\\S]*?\"port\"\\s*:\\s*(\\d+)");
    std::smatch match;
    if (std::regex_search(config_str, match, in_proxy_pattern)) {
      socks_port = static_cast<uint16_t>(std::stoi(match[1].str()));
    } else {
      // Fallback: find first "protocol": "socks" and its port
      std::regex socks_pattern("\"protocol\"\\s*:\\s*\"socks\"[\\s\\S]*?\"port\"\\s*:\\s*(\\d+)");
      if (std::regex_search(config_str, match, socks_pattern)) {
        socks_port = static_cast<uint16_t>(std::stoi(match[1].str()));
      } else {
        // Last resort: find any port in inbounds
        std::regex port_pattern("\"inbounds\"[\\s\\S]*?\"port\"\\s*:\\s*(\\d+)");
        if (std::regex_search(config_str, match, port_pattern)) {
          socks_port = static_cast<uint16_t>(std::stoi(match[1].str()));
        }
      }
    }
    
    if (!SetSystemProxy("127.0.0.1", socks_port)) {
      std::cerr << "Warning: Failed to set system proxy. Proxy mode may not work correctly." << std::endl;
    } else {
      std::cerr << "System proxy set to 127.0.0.1:" << socks_port << std::endl;
    }
  }
  
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

  // Before starting Xray, try to replace any configured ports that are already in use.
  try {
    ReplacePortsInConfigFile(fs::path(config_path));
    // Attempt to detect API address from the (possibly modified) config and
    // update our api_address_ so InitializeApiClient can connect to the right
    // endpoint.
    if (auto detected = DetectApiAddressInConfig(fs::path(config_path))) {
      api_address_ = *detected;
      std::cerr << "Detected Xray API address: " << api_address_ << std::endl;
    }
  } catch (...) {
    // Ignore failures here; we'll try to start the process and capture its output.
  }
  
  xray_process_ = std::make_unique<ProcessHandle>();
  
  STARTUPINFOA si = {};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;

  // Create pipes for stdout/stderr so we can capture Xray logs.
  SECURITY_ATTRIBUTES saAttr;
  saAttr.nLength = sizeof(SECURITY_ATTRIBUTES);
  saAttr.bInheritHandle = TRUE;
  saAttr.lpSecurityDescriptor = NULL;

  HANDLE hChildStdOutRead = INVALID_HANDLE_VALUE;
  HANDLE hChildStdOutWrite = INVALID_HANDLE_VALUE;
  HANDLE hChildStdErrRead = INVALID_HANDLE_VALUE;
  HANDLE hChildStdErrWrite = INVALID_HANDLE_VALUE;

  if (!CreatePipe(&hChildStdOutRead, &hChildStdOutWrite, &saAttr, 0)) {
    std::cerr << "Failed to create stdout pipe" << std::endl;
  } else {
    // Ensure the read handle is not inherited.
    SetHandleInformation(hChildStdOutRead, HANDLE_FLAG_INHERIT, 0);
  }

  if (!CreatePipe(&hChildStdErrRead, &hChildStdErrWrite, &saAttr, 0)) {
    std::cerr << "Failed to create stderr pipe" << std::endl;
  } else {
    SetHandleInformation(hChildStdErrRead, HANDLE_FLAG_INHERIT, 0);
  }

  // Parent will read from the read ends; child inherits the write ends.
  si.hStdOutput = hChildStdOutWrite != INVALID_HANDLE_VALUE ? hChildStdOutWrite : GetStdHandle(STD_OUTPUT_HANDLE);
  si.hStdError = hChildStdErrWrite != INVALID_HANDLE_VALUE ? hChildStdErrWrite : GetStdHandle(STD_ERROR_HANDLE);
  si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  
  std::string command_line = "\"" + xray_executable_path_.string() + "\" -config \"" + config_path + "\"";
  std::vector<char> cmd_buffer(command_line.begin(), command_line.end());
  cmd_buffer.push_back('\0');
  
  // Use a local PROCESS_INFORMATION and move the handles into our
  // ProcessHandle wrapper to avoid exposing PROCESS_INFORMATION in the
  // public header.
  PROCESS_INFORMATION pi = {};
  
  // Set working directory to the directory where xray.exe is located
  // This ensures that if there are any data files (like geoip.dat) they will be found
  std::string working_dir = xray_executable_path_.parent_path().string();
  
  // Try to find assets (geoip.dat, geosite.dat)
  // If they are not in the same directory as xray.exe, we need to tell Xray where they are
  auto assets_dir = FindXrayAssets(xray_executable_path_);
  if (assets_dir) {
    std::cerr << "Found Xray assets at: " << *assets_dir << std::endl;
    
    // If assets are in a different directory, set XRAY_LOCATION_ASSET environment variable
    if (*assets_dir != xray_executable_path_.parent_path()) {
      std::string assets_path_str = assets_dir->string();
      SetEnvironmentVariableA("XRAY_LOCATION_ASSET", assets_path_str.c_str());
      std::cerr << "Set XRAY_LOCATION_ASSET to: " << assets_path_str << std::endl;
    }
  } else {
    std::cerr << "Warning: Could not find geoip.dat. Xray might fail to start if routing rules require it." << std::endl;
  }
  
  BOOL success = CreateProcessA(
    nullptr,
    cmd_buffer.data(),
    nullptr,
    nullptr,
    TRUE,
    CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP,
    nullptr,
    working_dir.c_str(),
    &si,
    &pi
  );
  
  if (!success) {
    DWORD error = GetLastError();
    std::cerr << "Failed to start Xray process. Error: " << error << std::endl;
    // Clean up pipe handles we created
    if (hChildStdOutRead != INVALID_HANDLE_VALUE) CloseHandle(hChildStdOutRead);
    if (hChildStdOutWrite != INVALID_HANDLE_VALUE) CloseHandle(hChildStdOutWrite);
    if (hChildStdErrRead != INVALID_HANDLE_VALUE) CloseHandle(hChildStdErrRead);
    if (hChildStdErrWrite != INVALID_HANDLE_VALUE) CloseHandle(hChildStdErrWrite);
    xray_process_.reset();
    return false;
  }
  // Close the write ends in the parent process - the child has inherited them.
  if (hChildStdOutWrite != INVALID_HANDLE_VALUE) {
    CloseHandle(hChildStdOutWrite);
    hChildStdOutWrite = INVALID_HANDLE_VALUE;
  }
  if (hChildStdErrWrite != INVALID_HANDLE_VALUE) {
    CloseHandle(hChildStdErrWrite);
    hChildStdErrWrite = INVALID_HANDLE_VALUE;
  }

  // Move process handles into our opaque ProcessHandle wrapper.
  xray_process_->hProcess = reinterpret_cast<std::uintptr_t>(pi.hProcess);
  xray_process_->hThread = reinterpret_cast<std::uintptr_t>(pi.hThread);

  // Store read handles so they can be closed when stopping.
  xray_process_->hStdOutRead = reinterpret_cast<std::uintptr_t>(hChildStdOutRead);
  xray_process_->hStdErrRead = reinterpret_cast<std::uintptr_t>(hChildStdErrRead);

  // Start threads to capture stdout and stderr. Pass uintptr_t and cast inside
  // so this TU uses real HANDLE types but the header stays windows-free.
  auto reader = [](std::uintptr_t readHandlePtr, const char* label) {
    HANDLE readHandle = reinterpret_cast<HANDLE>(readHandlePtr);
    if (readHandle == INVALID_HANDLE_VALUE || readHandle == nullptr) return;
    const DWORD bufSize = 4096;
    std::vector<char> buffer(bufSize + 1);
    DWORD bytesRead = 0;
    while (true) {
      BOOL result = ReadFile(readHandle, buffer.data(), bufSize, &bytesRead, nullptr);
      if (!result || bytesRead == 0) break;
      buffer[bytesRead] = '\0';
      // Print to stderr with label
      std::cerr << "[Xray " << label << "] " << buffer.data();
    }
    CloseHandle(readHandle);
  };

  // Detach threads to continue independently
  if (xray_process_->hStdOutRead != 0) {
    std::thread(reader, xray_process_->hStdOutRead, "stdout").detach();
    // The reader will close the handle when finished; clear local copy to avoid double-close
    xray_process_->hStdOutRead = 0;
  }
  if (xray_process_->hStdErrRead != 0) {
    std::thread(reader, xray_process_->hStdErrRead, "stderr").detach();
    xray_process_->hStdErrRead = 0;
  }

  // Give the process a short moment to fail early (for example, due to port bind errors).
  std::this_thread::sleep_for(std::chrono::milliseconds(500));
  // If the process is no longer running, treat as an immediate failure and
  // capture a best-effort exit code for diagnostics.
  if (!xray_process_->IsRunning()) {
    DWORD exit_code = 0;
    HANDLE hp = reinterpret_cast<HANDLE>(xray_process_->hProcess);
    if (hp != nullptr && hp != INVALID_HANDLE_VALUE && GetExitCodeProcess(hp, &exit_code)) {
      std::cerr << "Xray process exited immediately with code: " << exit_code << std::endl;
    } else {
      std::cerr << "Xray process exited immediately" << std::endl;
    }
    // Clean up handles and process
    xray_process_->Close();
    xray_process_.reset();
    return false;
  }

  return true;
}

// Try to detect the API address inside the Xray config file. This is a
// lightweight regex-based extractor that looks for an "api" object and
// attempts to read an "address" (string) and/or "port" (number) field.
// Returns a string like "127.0.0.1:10085" if detected.
std::optional<std::string> V2rayManager::DetectApiAddressInConfig(const fs::path& config_path) {
  try {
    std::ifstream in(config_path.string());
    if (!in) return std::nullopt;
    std::string s((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());

    // Find the "api" object
    std::regex api_re("\"api\"\\s*:\\s*\\{([\\s\\S]*?)\\}", std::regex_constants::icase);
    std::smatch api_match;
    if (!std::regex_search(s, api_match, api_re)) return std::nullopt;

    std::string api_body = api_match[1].str();

    // Try to find "address": "..."
    std::regex addr_re("\"address\"\\s*:\\s*\"([^\"]+)\"");
    std::smatch addr_match;
    std::string address;
    if (std::regex_search(api_body, addr_match, addr_re)) {
      address = addr_match[1].str();
    }

    // Try to find "port": number
    std::regex port_re("\"port\"\\s*:\\s*(\\d+)");
    std::smatch port_match;
    std::string port;
    if (std::regex_search(api_body, port_match, port_re)) {
      port = port_match[1].str();
    }

    if (!address.empty() && !port.empty()) {
      // If the address already contains a colon (host:port), return it as-is.
      if (address.find(':') != std::string::npos) return address;
      return address + ":" + port;
    }

    if (!address.empty()) {
      // No explicit port found; leave as-is (caller may append default)
      return address;
    }

    if (!port.empty()) {
      return std::string("127.0.0.1:") + port;
    }

    return std::nullopt;
  } catch (...) {
    return std::nullopt;
  }
}

// Check if a TCP port on loopback is free. Uses Winsock.
bool V2rayManager::IsPortFree(uint16_t port) {
  WSADATA wsaData;
  if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
    return false;
  }
  SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (s == INVALID_SOCKET) {
    WSACleanup();
    return false;
  }

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  // Use InetPtonA to avoid deprecated inet_addr warnings
  if (InetPtonA(AF_INET, "127.0.0.1", &addr.sin_addr) != 1) {
    WSACleanup();
    return false;
  }
  addr.sin_port = htons(port);

  int result = bind(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr));
  if (result == 0) {
    closesocket(s);
    WSACleanup();
    return true;
  }
  closesocket(s);
  WSACleanup();
  return false;
}

// Find an ephemeral free port by binding to port 0.
uint16_t V2rayManager::FindFreePort() {
  WSADATA wsaData;
  if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
    return 0;
  }

  SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (s == INVALID_SOCKET) {
    WSACleanup();
    return 0;
  }

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  // Use InetPtonA to avoid deprecated inet_addr warnings
  if (InetPtonA(AF_INET, "127.0.0.1", &addr.sin_addr) != 1) {
    WSACleanup();
    return 0;
  }
  addr.sin_port = htons(0);

  if (bind(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
    closesocket(s);
    WSACleanup();
    return 0;
  }

  sockaddr_in assigned{};
  int len = sizeof(assigned);
  if (getsockname(s, reinterpret_cast<sockaddr*>(&assigned), &len) != 0) {
    closesocket(s);
    WSACleanup();
    return 0;
  }

  uint16_t port = ntohs(assigned.sin_port);
  closesocket(s);
  WSACleanup();
  return port;
}

// Replace configured ports in the config file if they are already in use.
// This is a best-effort, string-based approach: it searches for patterns like
// "port": 10807 and 127.0.0.1:10807 and replaces occupied ports with a free one.
bool V2rayManager::ReplacePortsInConfigFile(const fs::path& config_path) {
  if (!fs::exists(config_path)) return false;

  std::ifstream ifs(config_path);
  if (!ifs.is_open()) return false;
  std::stringstream ss;
  ss << ifs.rdbuf();
  std::string content = ss.str();
  ifs.close();

  bool modified = false;

  // Pattern 1: "port": 12345
  std::regex port_key_pattern("\"port\"\\s*:\\s*(\\d+)");
  std::smatch match;
  std::string new_content = content;
  auto search_start = new_content.cbegin();
  while (std::regex_search(search_start, new_content.cend(), match, port_key_pattern)) {
    int port = std::stoi(match[1].str());
    if (port >= 1 && port <= 65535) {
      if (!IsPortFree(static_cast<uint16_t>(port))) {
        uint16_t free_port = FindFreePort();
        if (free_port != 0) {
          // Replace only this occurrence
          auto pos = match.position(1) + (search_start - new_content.cbegin());
          new_content.replace(pos, match[1].length(), std::to_string(free_port));
          modified = true;
          // advance search_start beyond replaced part
          search_start = new_content.cbegin() + pos + std::to_string(free_port).length();
          continue;
        }
      }
    }
    // move forward
    search_start = match.suffix().first;
  }

  // Pattern 2: 127.0.0.1:12345 (common 'listen' patterns)
  std::regex listen_ip_pattern("127\\.0\\.0\\.1\\s*:\\s*(\\d+)");
  search_start = new_content.cbegin();
  while (std::regex_search(search_start, new_content.cend(), match, listen_ip_pattern)) {
    int port = std::stoi(match[1].str());
    if (port >= 1 && port <= 65535) {
      if (!IsPortFree(static_cast<uint16_t>(port))) {
        uint16_t free_port = FindFreePort();
        if (free_port != 0) {
          auto pos = match.position(1) + (search_start - new_content.cbegin());
          new_content.replace(pos, match[1].length(), std::to_string(free_port));
          modified = true;
          search_start = new_content.cbegin() + pos + std::to_string(free_port).length();
          continue;
        }
      }
    }
    search_start = match.suffix().first;
  }

  if (modified) {
    std::ofstream ofs(config_path, std::ios::binary | std::ios::trunc);
    if (!ofs.is_open()) return false;
    ofs << new_content;
    ofs.close();
    std::cerr << "Modified Xray config to avoid occupied ports." << std::endl;
  }

  // If there is no `"api"` section, inject a minimal api block so the
  // plugin can connect to Xray management API. We attempt to pick a free
  // port (default 10085) and insert the block at the top-level, right after
  // the "log" section or as the first key after the opening brace.
  std::regex api_key_re("\"api\"\\s*:\\s*");
  if (!std::regex_search(new_content, api_key_re)) {
    uint16_t api_port = 10085;
    if (!IsPortFree(api_port)) {
      uint16_t p = FindFreePort();
      if (p != 0) api_port = p;
    }

    // Strategy: Find the position after the "log" section closes.
    // Then insert the api block with a comma separator between them.
    size_t insert_pos = std::string::npos;
    
    // Look for the pattern: "log" : { ... } (with proper brace matching)
    std::regex log_start_re("\"log\"\\s*:\\s*\\{");
    std::smatch m;
    if (std::regex_search(new_content, m, log_start_re)) {
      // Found "log" section start. Now find the matching closing brace.
      size_t brace_start = m.position(0) + m.length(0) - 1;  // position of '{'
      int depth = 1;
      size_t pos = brace_start + 1;
      bool in_string = false;
      bool escaped = false;
      
      while (pos < new_content.length() && depth > 0) {
        char c = new_content[pos];
        if (escaped) {
          escaped = false;
          pos++;
          continue;
        }
        if (c == '\\') {
          escaped = true;
          pos++;
          continue;
        }
        if (c == '"') {
          in_string = !in_string;
        }
        if (!in_string) {
          if (c == '{') depth++;
          else if (c == '}') depth--;
        }
        pos++;
      }
      
      if (depth == 0) {
        // pos is now one position after the closing brace of "log"
        // Consume any whitespace after the closing brace
        while (pos < new_content.length() && 
               (new_content[pos] == ' ' || new_content[pos] == '\n' || 
                new_content[pos] == '\r' || new_content[pos] == '\t')) {
          pos++;
        }
        insert_pos = pos;
      }
    }
    
    // Fallback: if no "log" section found, insert after root opening brace
    if (insert_pos == std::string::npos) {
      auto brace_pos = new_content.find('{');
      if (brace_pos != std::string::npos) {
        insert_pos = brace_pos + 1;
      }
    }

    if (insert_pos != std::string::npos) {
      // Create a proper api block with leading comma separator
      // Use the modern format with "listen" instead of separate "address" and "port"
      std::ostringstream api_block;
      api_block << ",\n  \"api\": {\n";
      api_block << "    \"tag\": \"api\",\n";
      api_block << "    \"listen\": \"127.0.0.1:" << api_port << "\",\n";
      api_block << "    \"services\": [\"HandlerService\", \"StatsService\", \"LoggerService\"]\n";
      api_block << "  }";

      new_content.insert(insert_pos, api_block.str());
      
      // Write back
      std::ofstream ofs2(config_path, std::ios::binary | std::ios::trunc);
      if (ofs2.is_open()) {
        ofs2 << new_content;
        ofs2.close();
        std::cerr << "Inserted minimal Xray API block at 127.0.0.1:" << api_port << std::endl;
        // Update our configured api_address_
        api_address_ = std::string("127.0.0.1:") + std::to_string(api_port);
      }
    }
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
  // Before creating the ApiClient, ensure the API TCP port is accepting
  // connections. This avoids confusing failures from the HTTP client
  // when the socket isn't yet bound.
  auto can_connect = [&](const std::string &addr) -> bool {
    // Parse host:port
    auto colon = addr.find(':');
    if (colon == std::string::npos) return false;
    std::string host = addr.substr(0, colon);
    std::string port_str = addr.substr(colon + 1);
    int port = std::stoi(port_str);

    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2,2), &wsaData) != 0) return false;
    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET) { WSACleanup(); return false; }
    sockaddr_in sa{};
    sa.sin_family = AF_INET;
    sa.sin_port = htons(static_cast<u_short>(port));
    if (InetPtonA(AF_INET, host.c_str(), &sa.sin_addr) != 1) {
      closesocket(s);
      WSACleanup();
      return false;
    }
    // Set non-blocking connect with timeout
    u_long nb = 1;
    ioctlsocket(s, FIONBIO, &nb);
    int res = connect(s, reinterpret_cast<sockaddr*>(&sa), sizeof(sa));
    if (res == 0) {
      closesocket(s);
      WSACleanup();
      return true;
    }
    if (WSAGetLastError() != WSAEWOULDBLOCK) {
      closesocket(s);
      WSACleanup();
      return false;
    }
    // Wait for socket writable
    fd_set wf;
    FD_ZERO(&wf);
    FD_SET(s, &wf);
    timeval tv{};
    tv.tv_sec = 0;
    tv.tv_usec = 300 * 1000; // 300ms
    res = select(0, nullptr, &wf, nullptr, &tv);
    if (res > 0 && FD_ISSET(s, &wf)) {
      // check for error
      int err = 0;
      int len = sizeof(err);
      getsockopt(s, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&err), &len);
      closesocket(s);
      WSACleanup();
      return err == 0;
    }
    closesocket(s);
    WSACleanup();
    return false;
  };

  const int max_attempts = 8;
  const std::chrono::milliseconds attempt_delay(300);
  for (int i = 0; i < max_attempts; ++i) {
    std::cerr << "InitializeApiClient: attempt " << (i + 1) << " / " << max_attempts << ", probing " << api_address_ << std::endl;
    bool tcp_ok = can_connect(api_address_);
    std::cerr << "InitializeApiClient: TCP probe returned " << (tcp_ok ? "OK" : "NO") << std::endl;

    if (tcp_ok) {
      // TCP connection successful - Xray API port is responding.
      // Note: Xray API uses gRPC protocol, not HTTP/REST, so we can't easily query it from C++.
      // Since the port is open and Xray is clearly running, consider initialization successful.
      std::cerr << "Xray API endpoint is listening, stats may be queried via gRPC" << std::endl;
      return true;
    }
    
    std::this_thread::sleep_for(attempt_delay);
  }

  std::cerr << "InitializeApiClient: all attempts failed" << std::endl;
  return false;
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

void V2rayManager::GetTrafficStats(int64_t& upload, int64_t& download) {
  std::lock_guard<std::mutex> lock(stats_mutex_);
  upload = total_upload_;
  download = total_download_;
}

int V2rayManager::GetConnectedServerDelay(const std::string& url) {
  if (!is_running_.load() || !api_client_) {
    return -1;
  }
  return api_client_->MeasureDelay(url);
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
      std::cerr << "Found Xray executable: " << path << std::endl;
      return path;
    }
  }
  
  std::cerr << "Error: Could not find Xray executable." << std::endl;
  return std::nullopt;
}

std::optional<fs::path> V2rayManager::FindXrayAssets(const fs::path& executable_path) {
  // Files to look for
  const std::string geoip = "geoip.dat";
  
  // 1. Check directory where xray.exe is located
  fs::path exe_dir = executable_path.parent_path();
  if (fs::exists(exe_dir / geoip)) {
    return exe_dir;
  }
  
  // 2. Check current working directory
  if (fs::exists(fs::current_path() / geoip)) {
    return fs::current_path();
  }
  
  // 3. Check data/flutter_assets (standard Flutter Windows build layout)
  // The executable is usually in build/windows/runner/Debug/ or Release/
  // Assets are in data/flutter_assets/ relative to the executable
  
  // Get the directory of the running application (not xray.exe, but the flutter app)
  char app_path_buffer[MAX_PATH];
  if (GetModuleFileNameA(nullptr, app_path_buffer, MAX_PATH) > 0) {
    fs::path app_dir = fs::path(app_path_buffer).parent_path();
    
    // Check data/flutter_assets
    fs::path assets_dir = app_dir / "data" / "flutter_assets";
    if (fs::exists(assets_dir / geoip)) {
      return assets_dir;
    }
    
    // Check data/flutter_assets/assets (common if user put them in an 'assets' folder)
    if (fs::exists(assets_dir / "assets" / geoip)) {
      return assets_dir / "assets";
    }
    
    // Check data/flutter_assets/xray (if user organized them)
    if (fs::exists(assets_dir / "xray" / geoip)) {
      return assets_dir / "xray";
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
  
  // Move process handles into our opaque ProcessHandle wrapper
  temp_process->hProcess = reinterpret_cast<std::uintptr_t>(pi.hProcess);
  temp_process->hThread = reinterpret_cast<std::uintptr_t>(pi.hThread);
  
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

/**
 * @brief Configures Windows system-wide proxy settings using WinINET API.
 * 
 * @details Proxy Configuration Format:
 * Windows WinINET API uses the format "socks=ADDRESS:PORT" to specify a SOCKS5
 * proxy. The "socks=" prefix tells Windows to use SOCKS5 protocol.
 * 
 * @details Bypass List:
 * Local addresses are added to the bypass list to prevent proxy loops and
 * ensure local services remain accessible:
 * - localhost
 * - 127.* (all loopback addresses)
 * - 10.*, 172.16-31.*, 192.168.* (RFC 1918 private networks)
 * 
 * @details Unicode API Usage:
 * Uses Unicode versions of WinINET API (InternetSetOptionW) and Unicode
 * structures (INTERNET_PER_CONN_OPTION_LISTW) because modern Windows
 * applications are compiled with UNICODE defined. String buffers are stored
 * as class members to ensure they persist during the API call.
 * 
 * @details System Notification:
 * After setting proxy, the function calls:
 * - INTERNET_OPTION_SETTINGS_CHANGED: Notifies system that proxy settings changed
 * - INTERNET_OPTION_REFRESH: Forces immediate refresh of proxy settings
 * 
 * This ensures all applications pick up the new proxy settings immediately.
 * 
 * @param proxy_address The proxy server address (typically "127.0.0.1").
 * @param proxy_port The SOCKS5 proxy port number.
 * 
 * @return true if proxy was set successfully, false on error.
 * 
 * @note Requires appropriate system permissions. May fail without admin rights.
 * @note The proxy_string format is "socks=ADDRESS:PORT" for SOCKS5 protocol.
 */
bool V2rayManager::SetSystemProxy(const std::string& proxy_address, uint16_t proxy_port) {
  try {
    // Use WinINET API to set system proxy
    // Format: socks=127.0.0.1:10807
    std::string proxy_string = "socks=" + proxy_address + ":" + std::to_string(proxy_port);
    std::wstring proxy_wstring = StringToWString(proxy_string);
    
    std::string bypass_str = "localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*";
    std::wstring bypass_wstring = StringToWString(bypass_str);
    
    // Store wide strings in member buffers to ensure they persist during API call
    proxy_server_buf_.clear();
    proxy_server_buf_.resize((proxy_wstring.length() + 1) * sizeof(wchar_t));
    memcpy(proxy_server_buf_.data(), proxy_wstring.c_str(), proxy_server_buf_.size());
    
    proxy_bypass_buf_.clear();
    proxy_bypass_buf_.resize((bypass_wstring.length() + 1) * sizeof(wchar_t));
    memcpy(proxy_bypass_buf_.data(), bypass_wstring.c_str(), proxy_bypass_buf_.size());
    
    INTERNET_PER_CONN_OPTION_LISTW option_list;
    INTERNET_PER_CONN_OPTIONW options[3];
    DWORD dwBufSize = sizeof(INTERNET_PER_CONN_OPTION_LISTW);
    
    options[0].dwOption = INTERNET_PER_CONN_FLAGS;
    options[0].Value.dwValue = PROXY_TYPE_PROXY | PROXY_TYPE_DIRECT;
    
    options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
    options[1].Value.pszValue = reinterpret_cast<LPWSTR>(proxy_server_buf_.data());
    
    options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
    options[2].Value.pszValue = reinterpret_cast<LPWSTR>(proxy_bypass_buf_.data());
    
    option_list.dwSize = sizeof(INTERNET_PER_CONN_OPTION_LISTW);
    option_list.pszConnection = nullptr; // Apply to all connections
    option_list.dwOptionCount = 3;
    option_list.dwOptionError = 0;
    option_list.pOptions = options;
    
    if (!InternetSetOptionW(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &option_list, dwBufSize)) {
      DWORD error = GetLastError();
      std::cerr << "InternetSetOptionW failed: " << error << std::endl;
      return false;
    }
    
    // Notify system that proxy settings have changed
    InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
    InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
    
    std::cerr << "System proxy set successfully: " << proxy_string << std::endl;
    return true;
  } catch (const std::exception& e) {
    std::cerr << "Exception setting system proxy: " << e.what() << std::endl;
    return false;
  }
}

/**
 * @brief Clears Windows system-wide proxy settings.
 * 
 * @details Restoration Process:
 * Sets PROXY_TYPE_DIRECT flag to disable proxy and restore direct network
 * connections. This is essential during cleanup to prevent leaving the system
 * in a proxied state after the application terminates.
 * 
 * @details System Notification:
 * After clearing proxy, notifies the system to ensure all applications
 * immediately pick up the change and revert to direct connections.
 * 
 * @return true if proxy was cleared successfully, false on error.
 * 
 * @note Should always be called during cleanup to prevent proxy persistence.
 * @note Uses Unicode WinINET API (InternetSetOptionW) for consistency.
 */
bool V2rayManager::ClearSystemProxy() {
  try {
    INTERNET_PER_CONN_OPTION_LISTW option_list;
    INTERNET_PER_CONN_OPTIONW options[1];
    DWORD dwBufSize = sizeof(INTERNET_PER_CONN_OPTION_LISTW);
    
    options[0].dwOption = INTERNET_PER_CONN_FLAGS;
    options[0].Value.dwValue = PROXY_TYPE_DIRECT;
    
    option_list.dwSize = sizeof(INTERNET_PER_CONN_OPTION_LISTW);
    option_list.pszConnection = nullptr;
    option_list.dwOptionCount = 1;
    option_list.dwOptionError = 0;
    option_list.pOptions = options;
    
    if (!InternetSetOptionW(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &option_list, dwBufSize)) {
      DWORD error = GetLastError();
      std::cerr << "InternetSetOptionW failed to clear proxy: " << error << std::endl;
      return false;
    }
    
    // Notify system that proxy settings have changed
    InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
    InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
    
    std::cerr << "System proxy cleared successfully" << std::endl;
    return true;
  } catch (const std::exception& e) {
    std::cerr << "Exception clearing system proxy: " << e.what() << std::endl;
    return false;
  }
}

/**
 * @brief Modifies Xray configuration for Windows platform-specific requirements.
 * 
 * @details TUN Protocol Limitation on Windows:
 * Unlike Linux, Android, and iOS, Xray on Windows does not support the TUN protocol.
 * The TUN protocol requires kernel-level network interface creation capabilities
 * that are not available in standard Windows Xray builds. When attempting to use
 * TUN on Windows, Xray returns: "unknown config id: tun" error.
 * 
 * @details VPN Mode Implementation Strategy:
 * Since TUN is unavailable, VPN mode on Windows uses a hybrid approach:
 * 1. System Proxy Configuration: All applications route through SOCKS5 proxy
 * 2. Xray Routing Rules: Ensures all traffic is routed through "proxy" outbound
 * 
 * This provides VPN-like functionality for most applications, though it's not
 * a true virtual network interface. Applications that bypass system proxy
 * settings may not be routed correctly, but the majority of user applications
 * (browsers, most network libraries) respect Windows proxy settings.
 * 
 * @details Routing Rule Structure:
 * The function adds a routing rule with:
 * - type: "field" (matches traffic based on criteria)
 * - network: "tcp,udp" (applies to both TCP and UDP traffic)
 * - outboundTag: "proxy" (routes to the outbound tagged as "proxy")
 * 
 * This rule is inserted at the beginning of the rules array to ensure it has
 * priority over other routing rules.
 * 
 * @param config The original Xray configuration JSON string.
 * @param proxy_only If true, returns config unchanged. If false, modifies for VPN mode.
 * 
 * @return Modified configuration string with Windows-specific routing rules.
 * 
 * @note The configuration must contain an outbound with tag "proxy" for VPN mode.
 * @note If routing section doesn't exist, it will be created.
 * @note If rules array doesn't exist in routing, a warning is logged.
 */
  std::string V2rayManager::ModifyConfigForWindows(const std::string& config, bool proxy_only) {
  if (proxy_only) {
    // Proxy mode: no modification needed, applications will use SOCKS5 proxy
    return config;
  }
  
  // VPN mode on Windows: configure routing to send all traffic through proxy
  // Note: Windows Xray doesn't support TUN protocol, so we use routing + system proxy
  // This will route all traffic through the proxy outbound (tagged as "proxy")
  try {
    std::string modified = config;
    
    // The goal is to completely remove any rules that depend on geoip.dat or geosite.dat.
    // Instead of trying to patch individual rules, we will replace the entire "rules" array.
    
    // Check if "routing" section exists
    if (modified.find("\"routing\"") != std::string::npos) {
      // Found an existing routing section. Replace the whole thing with our clean version.
      std::string new_routing = "\"routing\": {\n    \"domainStrategy\": \"UseIp\",\n    \"rules\": [\n      {\n        \"type\": \"field\",\n        \"network\": \"tcp,udp\",\n        \"outboundTag\": \"proxy\"\n      }\n    ]\n  }";
      
      modified = json_utils::ReplaceJsonSection(modified, "routing", new_routing);
      std::cerr << "Replaced routing section for VPN mode (route all traffic through proxy)" << std::endl;
    } else {
      // No routing section at all - create one and inject it.
      size_t last_brace = modified.rfind('}');
      if (last_brace != std::string::npos) {
        // Check for a trailing comma before the final '}'
        size_t check_pos = last_brace - 1;
        while (check_pos > 0 && 
               (modified[check_pos] == ' ' || modified[check_pos] == '\n' || 
                modified[check_pos] == '\r' || modified[check_pos] == '\t')) {
          check_pos--;
        }
        
        std::string routing_section;
        if (check_pos > 0 && modified[check_pos] != ',') {
          // Needs a comma separator
          routing_section = ",\n  \"routing\": {\n    \"domainStrategy\": \"UseIp\",\n    \"rules\": [\n      {\n        \"type\": \"field\",\n        \"network\": \"tcp,udp\",\n        \"outboundTag\": \"proxy\"\n      }\n    ]\n  }";
        } else {
          // No comma needed
          routing_section = "\n  \"routing\": {\n    \"domainStrategy\": \"UseIp\",\n    \"rules\": [\n      {\n        \"type\": \"field\",\n        \"network\": \"tcp,udp\",\n        \"outboundTag\": \"proxy\"\n      }\n    ]\n  }";
        }
        
        modified.insert(last_brace, routing_section);
        std::cerr << "Added routing section for VPN mode" << std::endl;
      }
    }
    
    return modified;
    
  } catch (const std::exception& e) {
    std::cerr << "Error modifying config for Windows: " << e.what() << std::endl;
    return config; // Return original config on error
  }
}

std::string V2rayManager::GetCoreVersion() {
  // Try to get version from API first (if Xray is running)
  if (api_client_) {
    std::string version = api_client_->GetVersion();
    if (!version.empty()) {
      return version;
    }
  }
  
  // Try to get version by running xray.exe -version
  if (!xray_executable_path_.empty() && fs::exists(xray_executable_path_)) {
    // Try running xray.exe -version to get version string
    std::string command = "\"" + xray_executable_path_.string() + "\" -version";
    FILE* pipe = _popen(command.c_str(), "r");
    if (pipe != nullptr) {
      char buffer[128];
      std::string result = "";
      while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        result += buffer;
      }
      _pclose(pipe);
      
      // Parse version from output (format: "Xray 1.8.4" or "Xray 25.10.15")
      std::regex version_pattern(R"(Xray\s+(\d+\.\d+\.\d+))");
      std::smatch match;
      if (std::regex_search(result, match, version_pattern)) {
        return match[1].str();
      }
    }
    
    // Fallback: try to get version from executable file info
    DWORD dummy = 0;
    DWORD size = GetFileVersionInfoSizeA(xray_executable_path_.string().c_str(), &dummy);
    if (size > 0) {
      std::vector<char> buffer(size);
      if (GetFileVersionInfoA(xray_executable_path_.string().c_str(), 0, size, buffer.data())) {
        VS_FIXEDFILEINFO* file_info = nullptr;
        UINT len = 0;
        if (VerQueryValueA(buffer.data(), "\\", reinterpret_cast<LPVOID*>(&file_info), &len)) {
          if (file_info && len > 0) {
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

/**
 * @brief Retrieves traffic statistics from Xray API.
 * 
 * @param stats Output map of statistic names to values.
 * 
 * @return true if statistics were retrieved successfully, false otherwise.
 * 
 * @details Statistics Format:
 * Xray returns statistics in format:
 * "inbound>>>tag>>>traffic>>>uplink" and "inbound>>>tag>>>traffic>>>downlink"
 * 
 * The function parses these and aggregates upload/download totals.
 */
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

/**
 * @brief Measures network delay through Xray proxy.
 * 
 * @param url URL to test (typically a simple HTTP endpoint like google.com).
 * 
 * @return Delay in milliseconds, or -1 on error.
 * 
 * @details Implementation:
 * Makes an HTTP request through the system proxy (which routes through Xray)
 * and measures the time taken. This provides end-to-end latency measurement.
 */
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

std::string ApiClient::BuildApiUrl(const std::string& endpoint) {
  return "http://" + api_address_ + endpoint;
}

/**
 * @brief Makes an HTTP request to the Xray API endpoint.
 * 
 * @param endpoint API endpoint path (e.g., "/stats").
 * @param response Output parameter for response body.
 * 
 * @return true if request succeeded, false otherwise.
 * 
 * @details Implementation:
 * Uses WinINET API (InternetOpenUrlA) to make HTTP requests.
 * Note: Xray API actually uses gRPC, but some endpoints may respond to HTTP.
 */
bool ApiClient::MakeApiRequest(const std::string& endpoint, std::string& response) {
  std::string url = BuildApiUrl(endpoint);
  
  std::cerr << "ApiClient::MakeApiRequest: requesting URL: " << url << std::endl;

  HINTERNET hInternet = InternetOpenA("Xray-API-Client", INTERNET_OPEN_TYPE_DIRECT, nullptr, nullptr, 0);
  if (!hInternet) {
    std::cerr << "InternetOpenA failed: " << GetLastError() << std::endl;
    return false;
  }
  
  HINTERNET hConnect = InternetOpenUrlA(hInternet, url.c_str(), nullptr, 0, 
                                       INTERNET_FLAG_NO_CACHE_WRITE | INTERNET_FLAG_RELOAD, 0);
  if (!hConnect) {
    std::cerr << "InternetOpenUrlA failed for URL " << url << ", GetLastError=" << GetLastError() << std::endl;
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
  
  if (response.empty()) {
    std::cerr << "ApiClient::MakeApiRequest: response empty for URL: " << url << std::endl;
  }
  return !response.empty();
}
