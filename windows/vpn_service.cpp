#include "vpn_service.h"
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
#include <algorithm>
#include <regex>
#include <vector>

#pragma comment(lib, "Ws2_32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "version.lib")

VpnService::VpnService() {
  xray_executable_path_ = FindXrayExecutable().value_or(fs::path());
  if (!xray_executable_path_.empty()) {
    std::cerr << "VpnService: Found Xray executable at: " << xray_executable_path_ << std::endl;
  } else {
    std::cerr << "VpnService: WARNING - Xray executable not found!" << std::endl;
  }
  
  tun2socks_executable_path_ = FindTun2SocksExecutable().value_or(fs::path());
  if (!tun2socks_executable_path_.empty()) {
    std::cerr << "VpnService: Found Tun2Socks executable at: " << tun2socks_executable_path_ << std::endl;
  } else {
    std::cerr << "VpnService: WARNING - Tun2Socks executable not found!" << std::endl;
  }
}

VpnService::~VpnService() {
  Stop();
  if (!temp_config_path_.empty() && fs::exists(temp_config_path_)) {
    try { fs::remove(temp_config_path_); } catch (...) {}
  }
}

bool VpnService::Start(const std::string& config) {
  if (is_running_.load()) {
    Stop();
  }

  current_config_ = config;
  
  if (xray_executable_path_.empty()) {
    std::cerr << "Xray executable not found." << std::endl;
    return false;
  }
  
  if (tun2socks_executable_path_.empty()) {
    std::cerr << "Tun2Socks executable not found." << std::endl;
    return false;
  }

  is_running_.store(true);
  vpn_thread_ = std::thread(&VpnService::RunVpn, this);
  
  return true;
}

void VpnService::Stop() {
  if (!is_running_.load()) {
    return;
  }

  is_running_.store(false);
  
  if (vpn_thread_.joinable()) {
    vpn_thread_.join();
  }
  
  if (stats_thread_.joinable()) {
    stats_thread_.join();
  }
  
  StopProcesses();
  
  if (!temp_config_path_.empty() && fs::exists(temp_config_path_)) {
    try { fs::remove(temp_config_path_); } catch (...) {}
  }
}

bool VpnService::IsRunning() const {
  return is_running_.load();
}

void VpnService::RunVpn() {
  // 1. Prepare Xray Config with API injection
  std::string config_with_api = InjectApiConfig(current_config_);
  
  fs::path config_path;
  if (!WriteConfigToFile(config_with_api, config_path)) {
    std::cerr << "Failed to write Xray config for VPN" << std::endl;
    is_running_.store(false);
    return;
  }
  temp_config_path_ = config_path;

  // 2. Start Xray
  if (!StartXrayProcess(config_path.string())) {
    std::cerr << "Failed to start Xray for VPN" << std::endl;
    is_running_.store(false);
    return;
  }
  
  std::cerr << "VPN Service: Xray started successfully" << std::endl;

  // Give Xray a moment to start
  std::this_thread::sleep_for(std::chrono::milliseconds(1000));

  // 3. Find SOCKS port from config
  uint16_t socks_port = 10808; // Default
  {
    std::string config_str = current_config_;
    
    std::cerr << "VPN Service: Analyzing config to find SOCKS port..." << std::endl;
    
    // Try multiple patterns to find SOCKS inbound
    std::regex tagged_socks("\"tag\"\\s*:\\s*\"(?:in_proxy|socks-in|socks)\"[\\s\\S]*?\"port\"\\s*:\\s*(\\d+)");
    std::smatch match;
    
    if (std::regex_search(config_str, match, tagged_socks)) {
      socks_port = static_cast<uint16_t>(std::stoi(match[1].str()));
      std::cerr << "VPN Service: Found tagged SOCKS inbound on port " << socks_port << std::endl;
    } else {
      std::regex any_socks("\"protocol\"\\s*:\\s*\"socks\"[\\s\\S]{0,500}?\"port\"\\s*:\\s*(\\d+)");
      if (std::regex_search(config_str, match, any_socks)) {
        socks_port = static_cast<uint16_t>(std::stoi(match[1].str()));
        std::cerr << "VPN Service: Found SOCKS protocol on port " << socks_port << std::endl;
      } else {
        std::regex reverse_socks("\"port\"\\s*:\\s*(\\d+)[\\s\\S]{0,300}?\"protocol\"\\s*:\\s*\"socks\"");
        if (std::regex_search(config_str, match, reverse_socks)) {
          socks_port = static_cast<uint16_t>(std::stoi(match[1].str()));
          std::cerr << "VPN Service: Found SOCKS port (reverse search) " << socks_port << std::endl;
        } else {
          std::cerr << "VPN Service: WARNING - Could not find SOCKS inbound in config, using default port " << socks_port << std::endl;
        }
      }
    }
  }
  
  std::cerr << "VPN Service: Xray SOCKS port detected as " << socks_port << std::endl;

  // 4. Start Tun2Socks with IP configuration
  if (!StartTun2SocksProcess(socks_port)) {
    std::cerr << "Failed to start Tun2Socks" << std::endl;
    StopProcesses();
    is_running_.store(false);
    return;
  }

  // 5. Configure TUN interface IP and routing
  std::this_thread::sleep_for(std::chrono::milliseconds(2000)); // Wait for TUN to be ready
  
  std::cerr << "VPN Service: Configuring TUN interface..." << std::endl;
  
  std::string set_ip_cmd = "netsh interface ip set address name=\"flutter_vless_tun\" source=static addr=10.0.85.2 mask=255.255.255.0 gateway=none";
  std::cerr << "VPN Service: Executing: " << set_ip_cmd << std::endl;
  system(set_ip_cmd.c_str());
  
  // CRITICAL: Add bypass route for VPN server BEFORE adding default route
  // This prevents routing loop where VPN server traffic goes through TUN
  std::string server_address = ExtractServerAddress(current_config_);
  if (!server_address.empty()) {
    std::cerr << "VPN Service: Extracting server address: " << server_address << std::endl;
    
    // Resolve server address to IP if it's a domain
    std::string server_ip = ResolveToIP(server_address);
    if (!server_ip.empty()) {
      std::cerr << "VPN Service: Resolved server to IP: " << server_ip << std::endl;
      
      // Get default gateway
      std::string default_gateway = GetDefaultGateway();
      if (!default_gateway.empty()) {
        std::cerr << "VPN Service: Default gateway: " << default_gateway << std::endl;
        
        // Add route for VPN server through physical interface
        std::string delete_bypass_route_cmd = "route DELETE " + server_ip;
        system(delete_bypass_route_cmd.c_str());
        
        std::string bypass_route_cmd = "route ADD " + server_ip + " MASK 255.255.255.255 " + default_gateway + " METRIC 1";
        std::cerr << "VPN Service: Adding bypass route: " << bypass_route_cmd << std::endl;
        system(bypass_route_cmd.c_str());
        
        // Add routes for DNS servers (8.8.8.8, 1.1.1.1) to prevent loops when using "direct" outbound
        std::string delete_dns1_cmd = "route DELETE 8.8.8.8";
        std::string delete_dns2_cmd = "route DELETE 1.1.1.1";
        system(delete_dns1_cmd.c_str());
        system(delete_dns2_cmd.c_str());
        
        std::string dns1_route_cmd = "route ADD 8.8.8.8 MASK 255.255.255.255 " + default_gateway + " METRIC 1";
        std::string dns2_route_cmd = "route ADD 1.1.1.1 MASK 255.255.255.255 " + default_gateway + " METRIC 1";
        std::cerr << "VPN Service: Adding DNS bypass routes..." << std::endl;
        system(dns1_route_cmd.c_str());
        system(dns2_route_cmd.c_str());
      } else {
        std::cerr << "VPN Service: WARNING - Could not find default gateway for bypass route" << std::endl;
      }
    } else {
      std::cerr << "VPN Service: WARNING - Could not resolve server address" << std::endl;
    }
  } else {
    std::cerr << "VPN Service: WARNING - Could not extract server address from config" << std::endl;
  }
  
  std::string add_route_cmd = "netsh interface ip add route 0.0.0.0/0 \"flutter_vless_tun\" 10.0.85.1 metric=1";
  std::cerr << "VPN Service: Adding default route: " << add_route_cmd << std::endl;
  system(add_route_cmd.c_str());
  
  // Wait a moment for interface to settle
  std::this_thread::sleep_for(std::chrono::milliseconds(500));
  
  // Add DNS servers for TUN interface (use Google DNS and Cloudflare DNS)
  // Use 'ipv4' explicitly instead of 'ip' which might be ambiguous or default to something else
  std::string dns_cmd1 = "netsh interface ipv4 set dns name=\"flutter_vless_tun\" static 8.8.8.8 primary validate=no";
  std::string dns_cmd2 = "netsh interface ipv4 add dns name=\"flutter_vless_tun\" 1.1.1.1 index=2 validate=no";
  std::cerr << "VPN Service: Configuring DNS servers for TUN interface..." << std::endl;
  system(dns_cmd1.c_str());
  system(dns_cmd2.c_str());
  std::cerr << "VPN Service: DNS servers configured (8.8.8.8, 1.1.1.1)" << std::endl;
  
  std::cerr << "VPN Service: TUN interface configured and default route added" << std::endl;

  // Start stats thread
  stats_thread_ = std::thread(&VpnService::UpdateTrafficStats, this);

  // Monitor processes
  while (is_running_.load()) {
    if (xray_process_ && !xray_process_->IsRunning()) {
      std::cerr << "Xray process exited unexpectedly" << std::endl;
      is_running_.store(false);
      break;
    }
    if (tun2socks_process_ && !tun2socks_process_->IsRunning()) {
      std::cerr << "Tun2Socks process exited unexpectedly" << std::endl;
      is_running_.store(false);
      break;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
  }
  
  StopProcesses();
}

bool VpnService::StartXrayProcess(const std::string& config_path) {
  xray_process_ = std::make_unique<ProcessHandle>();
  
  std::string command_line = "\"" + xray_executable_path_.string() + "\" -config \"" + config_path + "\"";
  std::vector<char> cmd_buffer(command_line.begin(), command_line.end());
  cmd_buffer.push_back('\0');
  
  // Create pipes to capture stdout and stderr
  HANDLE hChildStdOutRead = INVALID_HANDLE_VALUE;
  HANDLE hChildStdOutWrite = INVALID_HANDLE_VALUE;
  HANDLE hChildStdErrRead = INVALID_HANDLE_VALUE;
  HANDLE hChildStdErrWrite = INVALID_HANDLE_VALUE;

  SECURITY_ATTRIBUTES saAttr;
  saAttr.nLength = sizeof(SECURITY_ATTRIBUTES);
  saAttr.bInheritHandle = TRUE;
  saAttr.lpSecurityDescriptor = NULL;

  if (!CreatePipe(&hChildStdOutRead, &hChildStdOutWrite, &saAttr, 0)) {
    std::cerr << "VPN Service: Failed to create Xray stdout pipe" << std::endl;
  } else {
    SetHandleInformation(hChildStdOutRead, HANDLE_FLAG_INHERIT, 0);
  }

  if (!CreatePipe(&hChildStdErrRead, &hChildStdErrWrite, &saAttr, 0)) {
    std::cerr << "VPN Service: Failed to create Xray stderr pipe" << std::endl;
  } else {
    SetHandleInformation(hChildStdErrRead, HANDLE_FLAG_INHERIT, 0);
  }
  
  STARTUPINFOA si = {};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
  si.wShowWindow = SW_HIDE;
  si.hStdOutput = hChildStdOutWrite != INVALID_HANDLE_VALUE ? hChildStdOutWrite : GetStdHandle(STD_OUTPUT_HANDLE);
  si.hStdError = hChildStdErrWrite != INVALID_HANDLE_VALUE ? hChildStdErrWrite : GetStdHandle(STD_ERROR_HANDLE);
  si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  
  PROCESS_INFORMATION pi = {};
  
  std::string working_dir = xray_executable_path_.parent_path().string();
  
  // Set assets location env var if needed
  auto assets_dir = FindXrayAssets(xray_executable_path_);
  if (assets_dir && *assets_dir != xray_executable_path_.parent_path()) {
    SetEnvironmentVariableA("XRAY_LOCATION_ASSET", assets_dir->string().c_str());
  }

  if (!CreateProcessA(NULL, cmd_buffer.data(), NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, working_dir.c_str(), &si, &pi)) {
    if (hChildStdOutRead != INVALID_HANDLE_VALUE) CloseHandle(hChildStdOutRead);
    if (hChildStdOutWrite != INVALID_HANDLE_VALUE) CloseHandle(hChildStdOutWrite);
    if (hChildStdErrRead != INVALID_HANDLE_VALUE) CloseHandle(hChildStdErrRead);
    if (hChildStdErrWrite != INVALID_HANDLE_VALUE) CloseHandle(hChildStdErrWrite);
    return false;
  }
  
  // Close write ends in parent
  if (hChildStdOutWrite != INVALID_HANDLE_VALUE) CloseHandle(hChildStdOutWrite);
  if (hChildStdErrWrite != INVALID_HANDLE_VALUE) CloseHandle(hChildStdErrWrite);
  
  xray_process_->hProcess = reinterpret_cast<std::uintptr_t>(pi.hProcess);
  xray_process_->hThread = reinterpret_cast<std::uintptr_t>(pi.hThread);
  xray_process_->hStdOutRead = reinterpret_cast<std::uintptr_t>(hChildStdOutRead);
  xray_process_->hStdErrRead = reinterpret_cast<std::uintptr_t>(hChildStdErrRead);
  
  // Create threads to read stdout and stderr
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
      std::cerr << "[Xray " << label << "] " << buffer.data();
    }
    CloseHandle(readHandle);
  };

  if (xray_process_->hStdOutRead != 0) {
    std::thread(reader, xray_process_->hStdOutRead, "stdout").detach();
    xray_process_->hStdOutRead = 0;
  }
  if (xray_process_->hStdErrRead != 0) {
    std::thread(reader, xray_process_->hStdErrRead, "stderr").detach();
    xray_process_->hStdErrRead = 0;
  }
  
  return true;
}

bool VpnService::StartTun2SocksProcess(uint16_t socks_port) {
  tun2socks_process_ = std::make_unique<ProcessHandle>();
  
  // Command: tun2socks.exe -device "flutter_vless_tun" -proxy socks5://127.0.0.1:<port>
  // Switching back to IPv4 (127.0.0.1) as [::1] seems to cause connection refused errors on some systems
  // Xray usually listens on 0.0.0.0 or 127.0.0.1 as well, or we can force it.
  std::string proxy_arg = "socks5://127.0.0.1:" + std::to_string(socks_port);
  std::string command_line = "\"" + tun2socks_executable_path_.string() + 
                              "\" -device \"flutter_vless_tun\"" +
                              " -proxy " + proxy_arg +
                              " -loglevel info";
  
  std::cerr << "VPN Service: Starting Tun2Socks with command: " << command_line << std::endl;
  
  std::vector<char> cmd_buffer(command_line.begin(), command_line.end());
  cmd_buffer.push_back('\0');
  
  // Create pipes to capture stdout and stderr
  HANDLE hChildStdOutRead = INVALID_HANDLE_VALUE;
  HANDLE hChildStdOutWrite = INVALID_HANDLE_VALUE;
  HANDLE hChildStdErrRead = INVALID_HANDLE_VALUE;
  HANDLE hChildStdErrWrite = INVALID_HANDLE_VALUE;

  SECURITY_ATTRIBUTES saAttr;
  saAttr.nLength = sizeof(SECURITY_ATTRIBUTES);
  saAttr.bInheritHandle = TRUE;
  saAttr.lpSecurityDescriptor = NULL;

  if (!CreatePipe(&hChildStdOutRead, &hChildStdOutWrite, &saAttr, 0)) {
    std::cerr << "VPN Service: Failed to create stdout pipe" << std::endl;
  } else {
    SetHandleInformation(hChildStdOutRead, HANDLE_FLAG_INHERIT, 0);
  }

  if (!CreatePipe(&hChildStdErrRead, &hChildStdErrWrite, &saAttr, 0)) {
    std::cerr << "VPN Service: Failed to create stderr pipe" << std::endl;
  } else {
    SetHandleInformation(hChildStdErrRead, HANDLE_FLAG_INHERIT, 0);
  }
  
  STARTUPINFOA si = {};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdOutput = hChildStdOutWrite != INVALID_HANDLE_VALUE ? hChildStdOutWrite : GetStdHandle(STD_OUTPUT_HANDLE);
  si.hStdError = hChildStdErrWrite != INVALID_HANDLE_VALUE ? hChildStdErrWrite : GetStdHandle(STD_ERROR_HANDLE);
  si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  
  PROCESS_INFORMATION pi = {};
  
  // Tun2Socks needs admin rights
  if (!CreateProcessA(NULL, cmd_buffer.data(), NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
    DWORD error = GetLastError();
    std::cerr << "VPN Service: Failed to launch tun2socks. Error code: " << error << std::endl;
    std::cerr << "VPN Service: Make sure the application is running as Administrator!" << std::endl;
    
    if (hChildStdOutRead != INVALID_HANDLE_VALUE) CloseHandle(hChildStdOutRead);
    if (hChildStdOutWrite != INVALID_HANDLE_VALUE) CloseHandle(hChildStdOutWrite);
    if (hChildStdErrRead != INVALID_HANDLE_VALUE) CloseHandle(hChildStdErrRead);
    if (hChildStdErrWrite != INVALID_HANDLE_VALUE) CloseHandle(hChildStdErrWrite);
    return false;
  }
  
  // Close write ends in parent
  if (hChildStdOutWrite != INVALID_HANDLE_VALUE) CloseHandle(hChildStdOutWrite);
  if (hChildStdErrWrite != INVALID_HANDLE_VALUE) CloseHandle(hChildStdErrWrite);
  
  std::cerr << "VPN Service: Tun2Socks process started successfully (PID: " << pi.dwProcessId << ")" << std::endl;
  
  tun2socks_process_->hProcess = reinterpret_cast<std::uintptr_t>(pi.hProcess);
  tun2socks_process_->hThread = reinterpret_cast<std::uintptr_t>(pi.hThread);
  tun2socks_process_->hStdOutRead = reinterpret_cast<std::uintptr_t>(hChildStdOutRead);
  tun2socks_process_->hStdErrRead = reinterpret_cast<std::uintptr_t>(hChildStdErrRead);
  
  // Create threads to read stdout and stderr
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
      std::cerr << "[Tun2Socks " << label << "] " << buffer.data();
    }
    CloseHandle(readHandle);
  };

  if (tun2socks_process_->hStdOutRead != 0) {
    std::thread(reader, tun2socks_process_->hStdOutRead, "stdout").detach();
    tun2socks_process_->hStdOutRead = 0;
  }
  if (tun2socks_process_->hStdErrRead != 0) {
    std::thread(reader, tun2socks_process_->hStdErrRead, "stderr").detach();
    tun2socks_process_->hStdErrRead = 0;
  }
  
  return true;
}

void VpnService::StopProcesses() {
  if (tun2socks_process_) {
    tun2socks_process_->Close();
    tun2socks_process_.reset();
  }
  if (xray_process_) {
    xray_process_->Close();
    xray_process_.reset();
  }
}

// Helper to inject API config for stats
std::string VpnService::InjectApiConfig(const std::string& config) {
  std::string new_config = config;
  
  // Extract server address from config to add routing bypass
  std::string server_address = ExtractServerAddress(config);
  
  // Force Xray to listen on IPv4 (127.0.0.1) instead of IPv6 ([::1])
  // This is crucial because tun2socks is configured to connect to 127.0.0.1
  // and Xray might not accept IPv4 connections if bound explicitly to [::1]
  new_config = std::regex_replace(new_config, std::regex("\"listen\"\\s*:\\s*\"\\[::1\\]\""), "\"listen\": \"127.0.0.1\"");
  
  // 1. Ensure "stats": {} exists
  if (new_config.find("\"stats\"") == std::string::npos) {
    size_t first_brace = new_config.find('{');
    if (first_brace != std::string::npos) {
      new_config.insert(first_brace + 1, "\n\"stats\": {},");
    }
  }
  
  // 2. Ensure "policy" exists with stats enabled
  if (new_config.find("\"policy\"") == std::string::npos) {
    size_t first_brace = new_config.find('{');
    if (first_brace != std::string::npos) {
      new_config.insert(first_brace + 1, "\n\"policy\": { \"system\": { \"statsOutboundUplink\": true, \"statsOutboundDownlink\": true } },");
    }
  }
  
  // 3. Ensure "api" block exists
  if (new_config.find("\"api\"") == std::string::npos) {
    size_t first_brace = new_config.find('{');
    if (first_brace != std::string::npos) {
      new_config.insert(first_brace + 1, "\n\"api\": { \"tag\": \"api\", \"services\": [\"StatsService\"] },");
    }
  }
  
  // 4. Add DNS block to handle DNS resolution through VPN
  if (new_config.find("\"dns\"") == std::string::npos) {
    std::string dns_block = "\n\"dns\": {\n"
      "  \"servers\": [\n"
      "    \"8.8.8.8\",\n"
      "    \"1.1.1.1\"\n"
      "  ]\n"
      "},";
    
    size_t first_brace = new_config.find('{');
    if (first_brace != std::string::npos) {
      new_config.insert(first_brace + 1, dns_block);
      std::cerr << "VPN Service: Added DNS block (8.8.8.8, 1.1.1.1)" << std::endl;
    }
  }
  
  // 5. Add routing rules to bypass VPN server traffic
  if (!server_address.empty()) {
    // Check if server_address is an IP to use "ip" field instead of "domain"
    bool is_ip = std::regex_match(server_address, std::regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$"));
    std::string rule_field = is_ip ? "ip" : "domain";
    
    std::string routing_rule = "\n\"routing\": {\n"
      "  \"domainStrategy\": \"IPIfNonMatch\",\n"
      "  \"rules\": [\n"
      "    {\n"
      "      \"type\": \"field\",\n"
      "      \"inboundTag\": [\"api\"],\n"
      "      \"outboundTag\": \"api\"\n"
      "    },\n"
      "    {\n"
      "      \"type\": \"field\",\n"
      "      \"" + rule_field + "\": [\"" + server_address + "\"],\n"
      "      \"outboundTag\": \"direct\"\n"
      "    },\n"
      "    {\n"
      "      \"type\": \"field\",\n"
      "      \"ip\": [\"8.8.8.8\", \"1.1.1.1\"],\n"
      "      \"outboundTag\": \"direct\"\n"
      "    },\n"
      "    {\n"
      "      \"type\": \"field\",\n"
      "      \"network\": \"tcp,udp\",\n"
      "      \"outboundTag\": \"proxy\"\n"
      "    }\n"
      "  ]\n"
      "},";
    
    size_t first_brace = new_config.find('{');
    if (first_brace != std::string::npos) {
      new_config.insert(first_brace + 1, routing_rule);
      std::cerr << "VPN Service: Added routing rules - VPN server (" << server_address << ") -> direct, all other -> proxy" << std::endl;
    }
  }
  
  // 6. Add API inbound
  size_t inbounds_pos = new_config.find("\"inbounds\"");
  if (inbounds_pos != std::string::npos) {
    size_t bracket_pos = new_config.find('[', inbounds_pos);
    if (bracket_pos != std::string::npos) {
      std::string api_inbound = R"(
    {
      "tag": "api",
      "port": 10086,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" }
    },)";
      new_config.insert(bracket_pos + 1, api_inbound);
    }
  }
  
  return new_config;
}

bool VpnService::RunXrayApiCommand(const std::string& args, std::string& output) {
  if (xray_executable_path_.empty()) return false;
  
  std::string command = "\"" + xray_executable_path_.string() + "\" " + args;
  
  // Create pipe for stdout
  HANDLE hRead, hWrite;
  SECURITY_ATTRIBUTES sa;
  sa.nLength = sizeof(SECURITY_ATTRIBUTES);
  sa.bInheritHandle = TRUE;
  sa.lpSecurityDescriptor = NULL;
  
  if (!CreatePipe(&hRead, &hWrite, &sa, 0)) return false;
  SetHandleInformation(hRead, HANDLE_FLAG_INHERIT, 0);
  
  STARTUPINFOA si = {};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
  si.hStdOutput = hWrite;
  si.hStdError = hWrite; // Capture stderr too
  si.wShowWindow = SW_HIDE;
  
  PROCESS_INFORMATION pi = {};
  
  std::vector<char> cmd_buf(command.begin(), command.end());
  cmd_buf.push_back('\0');
  
  if (!CreateProcessA(NULL, cmd_buf.data(), NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
    CloseHandle(hRead);
    CloseHandle(hWrite);
    return false;
  }
  
  CloseHandle(hWrite); // Close write end in parent
  
  // Read output
  char buffer[4096];
  DWORD bytesRead;
  std::string result;
  
  while (ReadFile(hRead, buffer, sizeof(buffer) - 1, &bytesRead, NULL) && bytesRead > 0) {
    buffer[bytesRead] = '\0';
    result += buffer;
  }
  
  CloseHandle(hRead);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  
  output = result;
  return true;
}

void VpnService::GetTrafficStats(int64_t& upload, int64_t& download) {
  std::lock_guard<std::mutex> lock(stats_mutex_);
  upload = total_upload_;
  download = total_download_;
}

void VpnService::UpdateTrafficStats() {
  while (is_running_.load()) {
    std::string output;
    // Command: xray api statsquery -server=127.0.0.1:10086
    std::string args = "api statsquery -server=" + api_address_;
    
    if (RunXrayApiCommand(args, output)) {
      // DEBUG: Print raw output to see what we're getting
      std::cerr << "STATS RAW: " << output << std::endl;
      
      // Parse JSON output manually to avoid dependency issues
      // Format: { "stat": [ { "name": "...", "value": ... }, ... ] }
      
      int64_t new_uplink = 0;
      int64_t new_downlink = 0;
      
      // Simple regex parsing
      std::regex stat_pattern("\"name\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]*?\"value\"\\s*:\\s*(\\d+)");
      auto begin = std::sregex_iterator(output.begin(), output.end(), stat_pattern);
      auto end = std::sregex_iterator();
      
      for (std::sregex_iterator i = begin; i != end; ++i) {
        std::smatch match = *i;
        std::string name = match[1].str();
        int64_t value = std::stoll(match[2].str());
        
        // Match outbound proxy stats
        // Pattern: "outbound>>>proxy>>>traffic>>>uplink" or "outbound>>>proxy>>>traffic>>>downlink"
        if (name.find("outbound>>>proxy>>>traffic>>>uplink") != std::string::npos) {
          new_uplink += value;
        } else if (name.find("outbound>>>proxy>>>traffic>>>downlink") != std::string::npos) {
          new_downlink += value;
        }
        // Also match generic uplink/downlink if specific proxy stats are missing
        else if (new_uplink == 0 && name.find("uplink") != std::string::npos) {
           // Only add if we haven't found specific stats yet to avoid double counting
           // This is a fallback
        }
      }
      
      // DEBUG: Print parsed values
      if (new_uplink > 0 || new_downlink > 0) {
        std::cerr << "STATS PARSED: Up=" << new_uplink << " Down=" << new_downlink << std::endl;
      }
      
      {
        std::lock_guard<std::mutex> lock(stats_mutex_);
        total_upload_ = new_uplink;
        total_download_ = new_downlink;
      }
    }
    
    std::this_thread::sleep_for(std::chrono::seconds(1));
  }
}

bool VpnService::WriteConfigToFile(const std::string& config, fs::path& config_path) {
  try {
    fs::path temp_dir = fs::temp_directory_path() / "flutter_vless_vpn";
    fs::create_directories(temp_dir);
    auto now = std::chrono::system_clock::now();
    auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
    config_path = temp_dir / ("vpn_config_" + std::to_string(timestamp) + ".json");
    std::ofstream file(config_path, std::ios::binary);
    if (!file.is_open()) return false;
    file << config;
    return true;
  } catch (...) { return false; }
}

std::optional<fs::path> VpnService::FindXrayExecutable() {
  // Simplified search logic
  std::vector<fs::path> search_paths = {
    fs::current_path() / "xray.exe",
    fs::current_path() / "xray" / "xray.exe",
    fs::current_path() / "windows" / "xray" / "xray.exe",
  };
  
  char exe_path[MAX_PATH];
  if (GetModuleFileNameA(nullptr, exe_path, MAX_PATH) > 0) {
    fs::path exe_dir = fs::path(exe_path).parent_path();
    search_paths.push_back(exe_dir / "xray.exe");
    search_paths.push_back(exe_dir / "xray" / "xray.exe");
    search_paths.push_back(exe_dir / "data" / "flutter_assets" / "xray.exe");
    search_paths.push_back(exe_dir / "data" / "flutter_assets" / "xray" / "xray.exe");
    search_paths.push_back(exe_dir / "data" / "flutter_assets" / "windows" / "xray" / "xray.exe");
  }
  
  for (const auto& path : search_paths) {
    if (fs::exists(path)) return path;
  }
  return std::nullopt;
  
}

std::optional<fs::path> VpnService::FindTun2SocksExecutable() {
  // Look for tun2socks.exe in similar locations to xray.exe
  std::vector<fs::path> search_paths = {
    fs::current_path() / "tun2socks.exe",
    fs::current_path() / "xray" / "tun2socks.exe",
    fs::current_path() / "windows" / "xray" / "tun2socks.exe",
  };
  
  char exe_path[MAX_PATH];
  if (GetModuleFileNameA(nullptr, exe_path, MAX_PATH) > 0) {
    fs::path exe_dir = fs::path(exe_path).parent_path();
    search_paths.push_back(exe_dir / "tun2socks.exe");
    search_paths.push_back(exe_dir / "xray" / "tun2socks.exe");
    search_paths.push_back(exe_dir / "data" / "flutter_assets" / "tun2socks.exe");
    search_paths.push_back(exe_dir / "data" / "flutter_assets" / "xray" / "tun2socks.exe");
    search_paths.push_back(exe_dir / "data" / "flutter_assets" / "windows" / "xray" / "tun2socks.exe");
  }
  
  for (const auto& path : search_paths) {
    if (fs::exists(path)) return path;
  }
  return std::nullopt;
}

std::optional<fs::path> VpnService::FindXrayAssets(const fs::path& executable_path) {
  fs::path exe_dir = executable_path.parent_path();
  if (fs::exists(exe_dir / "geoip.dat")) return exe_dir;
  return std::nullopt;
}

// Extract VPN server address from Xray config
std::string VpnService::ExtractServerAddress(const std::string& config) {
  // Try multiple patterns to find server address
  std::vector<std::regex> patterns = {
    // Pattern 1: Look for "address" field in outbounds
    std::regex("\"outbounds\"[\\s\\S]{0,2000}?\"address\"\\s*:\\s*\"([^\"]+)\""),
    // Pattern 2: Look for protocol + address together
    std::regex("\"protocol\"\\s*:\\s*\"(?:vless|vmess|trojan|shadowsocks)\"[\\s\\S]{0,1000}?\"address\"\\s*:\\s*\"([^\"]+)\""),
    // Pattern 3: Look in vnext array
    std::regex("\"vnext\"[\\s\\S]{0,1000}?\"address\"\\s*:\\s*\"([^\"]+)\""),
    // Pattern 4: Look in servers array
    std::regex("\"servers\"[\\s\\S]{0,1000}?\"address\"\\s*:\\s*\"([^\"]+)\""),
  };
  
  std::smatch match;
  for (const auto& pattern : patterns) {
    if (std::regex_search(config, match, pattern)) {
      std::string address = match[1].str();
      // Skip localhost addresses
      if (address != "127.0.0.1" && address != "localhost" && address != "::1") {
        std::cerr << "VPN Service: Extracted server address: " << address << std::endl;
        return address;
      }
    }
  }
  
  std::cerr << "VPN Service: Could not extract server address. Dumping first 500 chars of config:" << std::endl;
  std::cerr << config.substr(0, std::min<size_t>(500, config.length())) << std::endl;
  
  return "";
}

// Resolve domain to IP address
std::string VpnService::ResolveToIP(const std::string& address) {
  // Check if already an IP address
  std::regex ip_pattern("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$");
  if (std::regex_match(address, ip_pattern)) {
    return address; // Already an IP
  }
  
  // Resolve domain name
  WSADATA wsaData;
  if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
    return "";
  }
  
  struct addrinfo hints = {};
  struct addrinfo* result = nullptr;
  hints.ai_family = AF_INET; // IPv4
  hints.ai_socktype = SOCK_STREAM;
  
  if (getaddrinfo(address.c_str(), nullptr, &hints, &result) == 0 && result != nullptr) {
    struct sockaddr_in* addr = reinterpret_cast<struct sockaddr_in*>(result->ai_addr);
    char ip_str[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &(addr->sin_addr), ip_str, INET_ADDRSTRLEN);
    std::string ip(ip_str);
    freeaddrinfo(result);
    WSACleanup();
    return ip;
  }
  
  if (result) freeaddrinfo(result);
  WSACleanup();
  return "";
}

// Get default gateway IP
std::string VpnService::GetDefaultGateway() {
  // Use ipconfig to get default gateway
  FILE* pipe = _popen("ipconfig", "r");
  if (!pipe) return "";
  
  char buffer[256];
  std::string result;
  while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
    result += buffer;
  }
  _pclose(pipe);
  
  // Look for "Default Gateway" line
  std::regex gateway_pattern("Default Gateway[^:]*:[\\s]+(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})");
  std::smatch match;
  
  if (std::regex_search(result, match, gateway_pattern)) {
    return match[1].str();
  }
  
  return "";
}
