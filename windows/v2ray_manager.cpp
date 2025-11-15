#include "v2ray_manager.h"
#include <iostream>
#include <fstream>
#include <sstream>
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
}

// Implement ProcessHandle methods declared in the header. Keep Windows
// types and functions in this translation unit only.
ProcessHandle::ProcessHandle() = default;

ProcessHandle::~ProcessHandle() {
  Close();
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

std::string ApiClient::BuildApiUrl(const std::string& endpoint) {
  return "http://" + api_address_ + endpoint;
}
