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
  s.source_files = 'Classes/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '11.0'
  s.osx.deployment_target = '11.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  s.libraries = 'resolv'
end
