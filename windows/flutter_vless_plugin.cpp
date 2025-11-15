#include "include/flutter_vless/flutter_vless_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <memory>
#include <sstream>
#include <thread>
#include <chrono>
#include <atomic>
#include <mutex>

#include "v2ray_manager.h"

namespace {

class FlutterVlessPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterVlessPlugin(flutter::PluginRegistrarWindows *registrar);
  virtual ~FlutterVlessPlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void StartStatusTimer();
  void StopStatusTimer();
  void UpdateStatus();

  flutter::PluginRegistrarWindows *registrar_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> status_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> status_sink_;
  std::unique_ptr<V2rayManager> v2ray_manager_;
  std::thread status_thread_;
  std::atomic<bool> is_running_{false};
  std::atomic<bool> should_stop_{false};
  std::mutex status_mutex_;
  std::chrono::steady_clock::time_point start_time_;
  int64_t total_upload_ = 0;
  int64_t total_download_ = 0;
  int64_t upload_speed_ = 0;
  int64_t download_speed_ = 0;
};

void FlutterVlessPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<FlutterVlessPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

FlutterVlessPlugin::FlutterVlessPlugin(flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar),
      v2ray_manager_(std::make_unique<V2rayManager>()) {
  auto method_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "flutter_vless",
          &flutter::StandardMethodCodec::GetInstance());

  method_channel->SetMethodCallHandler(
      [this](const auto &call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  status_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "flutter_vless/status",
          &flutter::StandardMethodCodec::GetInstance());

  auto status_handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue *arguments,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        status_sink_ = std::move(events);
        return nullptr;
      },
      [this](const flutter::EncodableValue *arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        status_sink_.reset();
        return nullptr;
      });

  status_channel_->SetStreamHandler(std::move(status_handler));
}

FlutterVlessPlugin::~FlutterVlessPlugin() {
  StopStatusTimer();
  if (v2ray_manager_) {
    v2ray_manager_->Stop();
  }
}

void FlutterVlessPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("requestPermission") == 0) {
    // On Windows, we typically don't need special VPN permissions
    // but we might need admin rights for TUN/TAP interface
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name().compare("initializeVless") == 0) {
    const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      // Initialize v2ray manager
      result->Success(flutter::EncodableValue(nullptr));
    } else {
      result->Error("INVALID_ARGUMENTS", "Invalid arguments for initializeVless");
    }
  } else if (method_call.method_name().compare("startVless") == 0) {
    const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      auto remark_it = arguments->find(flutter::EncodableValue("remark"));
      auto config_it = arguments->find(flutter::EncodableValue("config"));
      auto proxy_only_it = arguments->find(flutter::EncodableValue("proxy_only"));
      
      if (remark_it != arguments->end() && config_it != arguments->end()) {
        std::string remark = std::get<std::string>(remark_it->second);
        std::string config = std::get<std::string>(config_it->second);
        bool proxy_only = false;
        
        if (proxy_only_it != arguments->end()) {
          const auto* proxy_only_value = std::get_if<bool>(&proxy_only_it->second);
          if (proxy_only_value) {
            proxy_only = *proxy_only_value;
          }
        }

        std::thread([this, config, proxy_only]() {
          if (v2ray_manager_->Start(config, proxy_only)) {
            is_running_ = true;
            start_time_ = std::chrono::steady_clock::now();
            StartStatusTimer();
          }
        }).detach();

        result->Success(flutter::EncodableValue(nullptr));
      } else {
        result->Error("INVALID_ARGUMENTS", "Missing remark or config");
      }
    } else {
      result->Error("INVALID_ARGUMENTS", "Invalid arguments for startVless");
    }
  } else if (method_call.method_name().compare("stopVless") == 0) {
    StopStatusTimer();
    if (v2ray_manager_) {
      v2ray_manager_->Stop();
    }
    is_running_ = false;
    total_upload_ = 0;
    total_download_ = 0;
    upload_speed_ = 0;
    download_speed_ = 0;
    
    if (status_sink_) {
      flutter::EncodableList status;
      status.push_back(flutter::EncodableValue("0"));
      status.push_back(flutter::EncodableValue("0"));
      status.push_back(flutter::EncodableValue("0"));
      status.push_back(flutter::EncodableValue("0"));
      status.push_back(flutter::EncodableValue("0"));
      status.push_back(flutter::EncodableValue("DISCONNECTED"));
      status_sink_->Success(flutter::EncodableValue(status));
    }
    
    result->Success(flutter::EncodableValue(nullptr));
  } else if (method_call.method_name().compare("getServerDelay") == 0) {
    const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      auto config_it = arguments->find(flutter::EncodableValue("config"));
      auto url_it = arguments->find(flutter::EncodableValue("url"));
      
      if (config_it != arguments->end() && url_it != arguments->end()) {
        std::string config = std::get<std::string>(config_it->second);
        std::string url = std::get<std::string>(url_it->second);
        
        std::thread([this, config, url, result = std::move(result)]() {
          int delay = v2ray_manager_->GetServerDelay(config, url);
          result->Success(flutter::EncodableValue(delay));
        }).detach();
        return;
      }
    }
    result->Error("INVALID_ARGUMENTS", "Invalid arguments for getServerDelay");
  } else if (method_call.method_name().compare("getConnectedServerDelay") == 0) {
    const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      auto url_it = arguments->find(flutter::EncodableValue("url"));
      if (url_it != arguments->end()) {
        std::string url = std::get<std::string>(url_it->second);
        
        std::thread([this, url, result = std::move(result)]() {
          int delay = v2ray_manager_->GetConnectedServerDelay(url);
          result->Success(flutter::EncodableValue(delay));
        }).detach();
        return;
      }
    }
    result->Error("INVALID_ARGUMENTS", "Invalid arguments for getConnectedServerDelay");
  } else if (method_call.method_name().compare("getCoreVersion") == 0) {
    std::string version = v2ray_manager_->GetCoreVersion();
    result->Success(flutter::EncodableValue(version));
  } else {
    result->NotImplemented();
  }
}

void FlutterVlessPlugin::StartStatusTimer() {
  should_stop_ = false;
  status_thread_ = std::thread([this]() {
    while (!should_stop_ && is_running_) {
      UpdateStatus();
      std::this_thread::sleep_for(std::chrono::seconds(1));
    }
  });
}

void FlutterVlessPlugin::StopStatusTimer() {
  should_stop_ = true;
  if (status_thread_.joinable()) {
    status_thread_.join();
  }
}

void FlutterVlessPlugin::UpdateStatus() {
  if (!status_sink_ || !is_running_) {
    return;
  }

  std::lock_guard<std::mutex> lock(status_mutex_);
  
  auto now = std::chrono::steady_clock::now();
  auto duration = std::chrono::duration_cast<std::chrono::seconds>(
      now - start_time_).count();

  // Get traffic stats from v2ray manager
  int64_t current_upload = 0;
  int64_t current_download = 0;
  v2ray_manager_->GetTrafficStats(current_upload, current_download);

  upload_speed_ = current_upload - total_upload_;
  download_speed_ = current_download - total_download_;
  total_upload_ = current_upload;
  total_download_ = current_download;

  flutter::EncodableList status;
  status.push_back(flutter::EncodableValue(std::to_string(duration)));
  status.push_back(flutter::EncodableValue(std::to_string(upload_speed_)));
  status.push_back(flutter::EncodableValue(std::to_string(download_speed_)));
  status.push_back(flutter::EncodableValue(std::to_string(total_upload_)));
  status.push_back(flutter::EncodableValue(std::to_string(total_download_)));
  status.push_back(flutter::EncodableValue("CONNECTED"));

  status_sink_->Success(flutter::EncodableValue(status));
}

}  // namespace

// C++ registration entry point called by the generated plugin registrant.
void FlutterVlessPluginRegisterWithRegistrar(
  flutter::PluginRegistrar* registrar) {
  // The generated registrant passes a generic flutter::PluginRegistrar*.
  // Cast to the Windows-specific registrar and forward to the plugin
  // registration method.
  FlutterVlessPlugin::RegisterWithRegistrar(
    reinterpret_cast<flutter::PluginRegistrarWindows*>(registrar));
}

// Also provide the C-style registrar overload (used by some Flutter toolchains)
// to support builds that pass a FlutterDesktopPluginRegistrarRef.
void FlutterVlessPluginRegisterWithRegistrar(
  FlutterDesktopPluginRegistrarRef registrar) {
  FlutterVlessPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

