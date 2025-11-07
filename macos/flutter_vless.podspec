Pod::Spec.new do |s|
  s.name             = 'flutter_vless'
  s.version          = '0.0.1'
  s.summary          = 'VLESS plugin for Flutter (macOS).'
  s.description      = <<-DESC
A Flutter plugin that provides VLESS functionality for macOS.
  DESC
  s.homepage         = 'https://example.com/flutter_vless'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }


  s.source = { :path => '..' }


  s.source_files = 'Classes/**/*.swift'

  s.dependency 'FlutterMacOS'
  s.platform = :osx, '11.0'
  s.osx.deployment_target = '11.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  s.libraries = 'resolv'
end
# validation command:  pod lib lint flutter_vless.podspec --allow-warnings --no-clean