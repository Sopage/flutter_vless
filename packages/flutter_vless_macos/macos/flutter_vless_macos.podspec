Pod::Spec.new do |s|
  s.name             = 'flutter_vless_macos'
  s.version          = '1.0.0'
  s.summary          = 'macOS implementation of the flutter_vless plugin.'
  s.description      = <<-DESC
macOS implementation of the flutter_vless plugin.
                       DESC
  s.homepage         = 'https://github.com/XIIIFOX/flutter_vless/'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source = { :path => '..' }
  s.source_files = 'flutter_vless_macos/Sources/flutter_vless_macos/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.osx.deployment_target = '12.0'

  s.prepare_command = <<-CMD
    set -e
    FRAMEWORK_DIR="XRay.xcframework"
    FRAMEWORK_ZIP="XRay.xcframework.zip"

    if [ -d "$FRAMEWORK_DIR" ]; then
      exit 0
    fi

    DEFAULT_FRAMEWORK_URL="https://github.com/XIIIFOX/flutter_vless/releases/download/xray-macos-v26.5.9/XRay.xcframework.zip"
    FRAMEWORK_URL="${FLUTTER_VLESS_MACOS_FRAMEWORK_URL:-$DEFAULT_FRAMEWORK_URL}"
    FRAMEWORK_SHA256="${FLUTTER_VLESS_MACOS_FRAMEWORK_SHA256:-7362248085fa51231d633bd58eebd67c28a7e1dbca792bfa014bfc06e237fb0c}"

    rm -rf "$FRAMEWORK_DIR" "$FRAMEWORK_ZIP"

    curl -fL -A "Mozilla/5.0" -o "$FRAMEWORK_ZIP" "$FRAMEWORK_URL"

    if [ -n "$FRAMEWORK_SHA256" ]; then
      echo "$FRAMEWORK_SHA256  $FRAMEWORK_ZIP" | shasum -a 256 -c -
    else
      echo "flutter_vless_macos: FLUTTER_VLESS_MACOS_FRAMEWORK_SHA256 not set; checksum verification skipped." >&2
    fi

    unzip -q "$FRAMEWORK_ZIP"
    rm "$FRAMEWORK_ZIP"

    if [ ! -d "$FRAMEWORK_DIR" ]; then
      echo "flutter_vless_macos: extracted XRay.xcframework is invalid or incomplete." >&2
      exit 1
    fi
  CMD

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  s.libraries = 'resolv'
  s.vendored_frameworks = 'XRay.xcframework'
end
