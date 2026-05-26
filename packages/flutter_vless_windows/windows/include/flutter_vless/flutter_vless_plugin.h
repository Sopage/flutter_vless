#ifndef FLUTTER_PLUGIN_FLUTTER_VLESS_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_VLESS_PLUGIN_H_

#include <flutter/plugin_registrar.h>
#include <flutter/plugin_registrar_windows.h>

// Registers the plugin with the given registrar.
// The generated plugin registrant may pass either a C++ `flutter::PluginRegistrar*`
// or a C API `FlutterDesktopPluginRegistrarRef` depending on the toolchain.
void FlutterVlessPluginRegisterWithRegistrar(
    flutter::PluginRegistrar* registrar);

// C API variant (older toolchains) — declare here so the generated registrant
// sees a matching declaration when it passes a C API registrar reference.
void FlutterVlessPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#endif  // FLUTTER_PLUGIN_FLUTTER_VLESS_PLUGIN_H_

