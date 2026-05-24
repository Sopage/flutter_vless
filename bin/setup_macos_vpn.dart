import 'dart:io';
import 'dart:math';

const tunnelTargetName = 'XrayTunnel';
const tunnelProductName = 'flutter-vless-macos-tunnel-support';
const tunnelModuleName = 'flutter_vless_macos_tunnel_support';
const pluginPackageRelativePath =
    'Flutter/ephemeral/Packages/.packages/flutter_vless_macos';

void main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final appRoot = Directory(options.projectDir).absolute;
  final macosDir = Directory('${appRoot.path}/macos');
  final pbxprojFile = File('${macosDir.path}/Runner.xcodeproj/project.pbxproj');

  if (!pbxprojFile.existsSync()) {
    _fail(
        'Could not find ${pbxprojFile.path}. Run this from a Flutter app root '
        'or pass --project-dir.');
  }
  if (options.bundleId == null || options.groupId == null) {
    _fail('Both --bundle-id and --group-id are required.');
  }

  await _ensureFlutterPackages(appRoot);
  _writeTunnelFiles(macosDir, options.groupId!);

  final project = _PbxProject(pbxprojFile.readAsStringSync());
  project.configure(
    bundleId: options.bundleId!,
    groupId: options.groupId!,
    teamId: options.teamId,
    deploymentTarget: options.deploymentTarget,
  );
  pbxprojFile.writeAsStringSync(project.text);

  stdout.writeln('macOS VPN setup complete.');
  stdout.writeln('Runner bundle id: ${options.bundleId}');
  stdout.writeln('Tunnel bundle id: ${options.bundleId}.$tunnelTargetName');
  stdout.writeln('App Group: ${options.groupId}');
  stdout.writeln('Next: open macos/Runner.xcworkspace and let Xcode resolve '
      'Swift packages/signing if it asks.');
}

void _printUsage() {
  stdout.writeln('''
Usage:
  dart run flutter_vless:setup_macos_vpn \\
    --bundle-id com.example.myapp \\
    --group-id group.com.example.myapp \\
    --team-id ABCDE12345

Options:
  --project-dir <path>          Flutter app root. Defaults to current directory.
  --deployment-target <value>   Defaults to 13.0.
  --team-id <id>                Optional, but recommended for automatic signing.
''');
}

Future<void> _ensureFlutterPackages(Directory appRoot) async {
  final packageLink = Link(
    '${appRoot.path}/macos/$pluginPackageRelativePath',
  );
  final packageDir = Directory(packageLink.path);
  if (packageLink.existsSync() || packageDir.existsSync()) {
    return;
  }

  stdout.writeln(
      'Flutter generated packages are missing; running flutter pub get...');
  final result = await Process.run(
    'flutter',
    ['pub', 'get'],
    workingDirectory: appRoot.path,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    _fail('flutter pub get failed.');
  }
}

void _writeTunnelFiles(Directory macosDir, String groupId) {
  final tunnelDir = Directory('${macosDir.path}/$tunnelTargetName');
  tunnelDir.createSync(recursive: true);

  File('${tunnelDir.path}/PacketTunnelProvider.swift').writeAsStringSync('''
import $tunnelModuleName

final class PacketTunnelProvider: FlutterVlessPacketTunnelProvider {}
''');

  File('${tunnelDir.path}/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>NSExtension</key>
\t<dict>
\t\t<key>NSExtensionPointIdentifier</key>
\t\t<string>com.apple.networkextension.packet-tunnel</string>
\t\t<key>NSExtensionPrincipalClass</key>
\t\t<string>\$(PRODUCT_MODULE_NAME).PacketTunnelProvider</string>
\t</dict>
\t<key>LSMinimumSystemVersion</key>
\t<string>\$(MACOSX_DEPLOYMENT_TARGET)</string>
</dict>
</plist>
''');

  File('${tunnelDir.path}/XrayTunnel.entitlements').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.developer.networking.networkextension</key>
\t<array>
\t\t<string>packet-tunnel-provider</string>
\t</array>
\t<key>com.apple.security.application-groups</key>
\t<array>
\t\t<string>$groupId</string>
\t</array>
</dict>
</plist>
''');

  for (final name in ['DebugProfile.entitlements', 'Release.entitlements']) {
    _ensureRunnerEntitlement(File('${macosDir.path}/Runner/$name'), groupId);
  }
}

void _ensureRunnerEntitlement(File file, String groupId) {
  if (!file.existsSync()) {
    file.createSync(recursive: true);
    file.writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.security.app-sandbox</key>
\t<false/>
\t<key>com.apple.developer.networking.networkextension</key>
\t<array>
\t\t<string>packet-tunnel-provider</string>
\t</array>
\t<key>com.apple.security.application-groups</key>
\t<array>
\t\t<string>$groupId</string>
\t</array>
</dict>
</plist>
''');
    return;
  }

  var content = file.readAsStringSync();

  content = _ensureEntitlementArrayValue(
    content: content,
    key: 'com.apple.developer.networking.networkextension',
    value: 'packet-tunnel-provider',
  );
  content = _ensureEntitlementArrayValue(
    content: content,
    key: 'com.apple.security.application-groups',
    value: groupId,
  );
  file.writeAsStringSync(content);
}

String _ensureEntitlementArrayValue({
  required String content,
  required String key,
  required String value,
}) {
  if (content.contains('<key>$key</key>') &&
      content.contains('<string>$value</string>')) {
    return content;
  }

  final arrayPattern = RegExp(
    '\\s*<key>${RegExp.escape(key)}</key>\\s*<array>',
  );
  final arrayMatch = arrayPattern.firstMatch(content);
  if (arrayMatch != null) {
    return content.replaceRange(
      arrayMatch.start,
      arrayMatch.end,
      '${arrayMatch.group(0)!}\n\t\t<string>$value</string>',
    );
  }

  return content.replaceFirst(
    '</dict>',
    '\t<key>$key</key>\n'
        '\t<array>\n'
        '\t\t<string>$value</string>\n'
        '\t</array>\n'
        '</dict>',
  );
}

class _PbxProject {
  _PbxProject(this.text);

  String text;
  final _random = Random.secure();

  void configure({
    required String bundleId,
    required String groupId,
    required String deploymentTarget,
    String? teamId,
  }) {
    final projectId = _requiredMatch(
      RegExp(r'rootObject = ([A-Z0-9]{24}) /\* Project object \*/;'),
      'project root',
    );
    final projectBlock = _objectBlock(projectId);
    final mainGroupId = _requiredMatchIn(
      projectBlock.text,
      RegExp(r'mainGroup = ([A-Z0-9]{24})(?: /\*)?'),
      'main group',
    );
    final productGroupId = _requiredMatchIn(
      projectBlock.text,
      RegExp(r'productRefGroup = ([A-Z0-9]{24}) /\*'),
      'products group',
    );
    final runnerTargetId = _targetId('Runner') ??
        (throw StateError('Could not find Runner target in project.pbxproj.'));
    final tunnelTargetId = _targetId(tunnelTargetName) ?? _id();

    final supportPackageId = _ensureLocalPackageReference();
    final supportProductId = _ensurePackageProductDependency(
      productName: tunnelProductName,
      packageId: supportPackageId,
    );
    final supportBuildFileId = _ensureProductBuildFile(
      productName: tunnelProductName,
      productId: supportProductId,
    );

    final networkFileId =
        _ensureFrameworkFileReference('NetworkExtension.framework');
    final networkBuildFileId = _ensureFrameworkBuildFile(
      name: 'NetworkExtension.framework',
      fileId: networkFileId,
    );

    final tunnelProductFileId = _ensureProductFileReference();
    final tunnelEmbedBuildFileId =
        _ensureExtensionEmbedBuildFile(tunnelProductFileId);
    final proxyId = _ensureContainerProxy(projectId, tunnelTargetId);
    final dependencyId = _ensureTargetDependency(proxyId, tunnelTargetId);

    String? tunnelFrameworksId;
    String? tunnelSourcesId;
    String? tunnelResourcesId;
    String? tunnelConfigListId;
    String? tunnelGroupId;

    if (_targetId(tunnelTargetName) == null) {
      tunnelFrameworksId = _id();
      tunnelSourcesId = _id();
      tunnelResourcesId = _id();
      tunnelConfigListId = _id();
      tunnelGroupId = _id();
      final providerFileId = _id();
      final infoFileId = _id();
      final entitlementsFileId = _id();
      final providerBuildFileId = _id();

      _addBuildFile(
        providerBuildFileId,
        'PacketTunnelProvider.swift in Sources',
        'fileRef = $providerFileId /* PacketTunnelProvider.swift */;',
      );
      _addFileReference(
        providerFileId,
        'PacketTunnelProvider.swift',
        'lastKnownFileType = sourcecode.swift; path = PacketTunnelProvider.swift; sourceTree = "<group>";',
      );
      _addFileReference(
        infoFileId,
        'Info.plist',
        'lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";',
      );
      _addFileReference(
        entitlementsFileId,
        'XrayTunnel.entitlements',
        'lastKnownFileType = text.plist.entitlements; path = XrayTunnel.entitlements; sourceTree = "<group>";',
      );
      _addGroup(
        tunnelGroupId,
        tunnelTargetName,
        [
          '$providerFileId /* PacketTunnelProvider.swift */',
          '$infoFileId /* Info.plist */',
          '$entitlementsFileId /* XrayTunnel.entitlements */',
        ],
        path: tunnelTargetName,
      );
      _appendListEntry(
          mainGroupId, 'children', '$tunnelGroupId /* $tunnelTargetName */');

      _addFrameworksPhase(tunnelFrameworksId, [
        '$supportBuildFileId /* $tunnelProductName in Frameworks */',
        '$networkBuildFileId /* NetworkExtension.framework in Frameworks */',
      ]);
      _addSourcesPhase(tunnelSourcesId, [
        '$providerBuildFileId /* PacketTunnelProvider.swift in Sources */',
      ]);
      _addResourcesPhase(tunnelResourcesId);
      _addNativeTarget(
        tunnelTargetId,
        tunnelConfigListId,
        tunnelSourcesId,
        tunnelFrameworksId,
        tunnelResourcesId,
        tunnelProductFileId,
        supportProductId,
      );
      _addBuildConfigurationList(
        tunnelConfigListId,
        'PBXNativeTarget "$tunnelTargetName"',
        bundleId,
        deploymentTarget,
        teamId,
      );
      _appendListEntry(
          projectId, 'targets', '$tunnelTargetId /* $tunnelTargetName */');
      _appendListEntry(productGroupId, 'children',
          '$tunnelProductFileId /* $tunnelTargetName.appex */');
      _ensureTargetAttributes(projectId, tunnelTargetId);
    }

    final actualTunnelTargetId = _targetId(tunnelTargetName)!;
    final tunnelBlock = _objectBlock(actualTunnelTargetId).text;
    tunnelFrameworksId ??= _requiredMatchIn(
      tunnelBlock,
      RegExp(r'([A-Z0-9]{24}) /\* Frameworks \*/'),
      'XrayTunnel Frameworks phase',
    );
    _appendListEntry(
      actualTunnelTargetId,
      'packageProductDependencies',
      '$supportProductId /* $tunnelProductName */',
    );
    _appendListEntry(
      tunnelFrameworksId,
      'files',
      '$supportBuildFileId /* $tunnelProductName in Frameworks */',
    );
    _appendListEntry(
      tunnelFrameworksId,
      'files',
      '$networkBuildFileId /* NetworkExtension.framework in Frameworks */',
    );

    _removeFrameworkFromTarget(actualTunnelTargetId, 'XRay.xcframework');
    _removeFrameworkFromTarget(actualTunnelTargetId, 'Tun2SocksKit');
    _removeProjectFileReferences('XRay.xcframework');

    final embedPhaseId = _ensureEmbedExtensionsPhase(runnerTargetId);
    _appendListEntry(
      embedPhaseId,
      'files',
      '$tunnelEmbedBuildFileId /* $tunnelTargetName.appex in Embed Foundation Extensions */',
    );
    _appendListEntry(
      runnerTargetId,
      'dependencies',
      '$dependencyId /* PBXTargetDependency */',
    );

    _appendListEntry(
      projectId,
      'packageReferences',
      '$supportPackageId /* XCLocalSwiftPackageReference "$pluginPackageRelativePath" */',
    );
    _patchAllMacOSDeploymentTargets(deploymentTarget);
    _patchRunnerBuildSettings(bundleId, groupId, deploymentTarget, teamId);
    _patchTunnelBuildSettings(bundleId, deploymentTarget, teamId);
  }

  String _ensureLocalPackageReference() {
    final existing = RegExp(
      r'([A-Z0-9]{24}) /\* XCLocalSwiftPackageReference "[^"]*flutter_vless_macos" \*/ = \{\s*isa = XCLocalSwiftPackageReference;\s*relativePath = [^;]*flutter_vless_macos;',
      multiLine: true,
    ).firstMatch(text);
    if (existing != null) return existing.group(1)!;

    final id = _id();
    _insertObject(
      'XCLocalSwiftPackageReference',
      '''
\t\t$id /* XCLocalSwiftPackageReference "$pluginPackageRelativePath" */ = {
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = $pluginPackageRelativePath;
\t\t};
''',
    );
    return id;
  }

  String _ensurePackageProductDependency({
    required String productName,
    required String packageId,
  }) {
    final existing = RegExp(
      '([A-Z0-9]{24}) /\\* $productName \\*/ = \\{[\\s\\S]*?productName = $productName;',
    ).firstMatch(text);
    if (existing != null) return existing.group(1)!;

    final id = _id();
    _insertObject(
      'XCSwiftPackageProductDependency',
      '''
\t\t$id /* $productName */ = {
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = $packageId /* XCLocalSwiftPackageReference "$pluginPackageRelativePath" */;
\t\t\tproductName = $productName;
\t\t};
''',
    );
    return id;
  }

  String _ensureProductBuildFile({
    required String productName,
    required String productId,
  }) {
    final existing = RegExp(
      '([A-Z0-9]{24}) /\\* $productName in Frameworks \\*/ = \\{isa = PBXBuildFile; productRef = $productId',
    ).firstMatch(text);
    if (existing != null) return existing.group(1)!;

    final id = _id();
    _addBuildFile(
      id,
      '$productName in Frameworks',
      'productRef = $productId /* $productName */;',
    );
    return id;
  }

  String _ensureFrameworkFileReference(String name) {
    final existing = RegExp(
      '([A-Z0-9]{24}) /\\* $name \\*/ = \\{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = $name;',
    ).firstMatch(text);
    if (existing != null) return existing.group(1)!;

    final id = _id();
    _addFileReference(
      id,
      name,
      'lastKnownFileType = wrapper.framework; name = $name; path = System/Library/Frameworks/$name; sourceTree = SDKROOT;',
    );
    return id;
  }

  String _ensureFrameworkBuildFile({
    required String name,
    required String fileId,
  }) {
    final existing = RegExp(
      '([A-Z0-9]{24}) /\\* $name in Frameworks \\*/ = \\{isa = PBXBuildFile; fileRef = $fileId',
    ).firstMatch(text);
    if (existing != null) return existing.group(1)!;

    final id = _id();
    _addBuildFile(id, '$name in Frameworks', 'fileRef = $fileId /* $name */;');
    return id;
  }

  String _ensureProductFileReference() {
    final existing = RegExp(
      r'([A-Z0-9]{24}) /\* XrayTunnel.appex \*/ = \{isa = PBXFileReference;',
    ).firstMatch(text);
    if (existing != null) return existing.group(1)!;

    final id = _id();
    _addFileReference(
      id,
      '$tunnelTargetName.appex',
      'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = $tunnelTargetName.appex; sourceTree = BUILT_PRODUCTS_DIR;',
    );
    return id;
  }

  String _ensureExtensionEmbedBuildFile(String fileId) {
    final existing = RegExp(
      '([A-Z0-9]{24}) /\\* $tunnelTargetName.appex in Embed Foundation Extensions \\*/ = \\{isa = PBXBuildFile; fileRef = $fileId',
    ).firstMatch(text);
    if (existing != null) return existing.group(1)!;

    final id = _id();
    _addBuildFile(
      id,
      '$tunnelTargetName.appex in Embed Foundation Extensions',
      'fileRef = $fileId /* $tunnelTargetName.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); };',
    );
    return id;
  }

  String _ensureContainerProxy(String projectId, String tunnelTargetId) {
    for (final match in RegExp(
      r'\t\t([A-Z0-9]{24}) /\* PBXContainerItemProxy \*/ = \{([\s\S]*?)\n\t\t\};',
    ).allMatches(text)) {
      final body = match.group(2)!;
      if (body.contains('remoteGlobalIDString = $tunnelTargetId;') &&
          body.contains('remoteInfo = $tunnelTargetName;')) {
        return match.group(1)!;
      }
    }

    final id = _id();
    _insertObject(
      'PBXContainerItemProxy',
      '''
\t\t$id /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = $projectId /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = $tunnelTargetId;
\t\t\tremoteInfo = $tunnelTargetName;
\t\t};
''',
    );
    return id;
  }

  String _ensureTargetDependency(String proxyId, String tunnelTargetId) {
    for (final match in RegExp(
      r'\t\t([A-Z0-9]{24}) /\* PBXTargetDependency \*/ = \{([\s\S]*?)\n\t\t\};',
    ).allMatches(text)) {
      final body = match.group(2)!;
      if (body.contains('target = $tunnelTargetId /* $tunnelTargetName */;') &&
          body.contains(
              'targetProxy = $proxyId /* PBXContainerItemProxy */;')) {
        return match.group(1)!;
      }
    }

    final id = _id();
    _insertObject(
      'PBXTargetDependency',
      '''
\t\t$id /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = $tunnelTargetId /* $tunnelTargetName */;
\t\t\ttargetProxy = $proxyId /* PBXContainerItemProxy */;
\t\t};
''',
    );
    return id;
  }

  String _ensureEmbedExtensionsPhase(String runnerTargetId) {
    final existing = RegExp(
      r'([A-Z0-9]{24}) /\* Embed Foundation Extensions \*/ = \{\s*isa = PBXCopyFilesBuildPhase;',
      multiLine: true,
    ).firstMatch(text);
    if (existing != null) {
      _appendListEntry(runnerTargetId, 'buildPhases',
          '${existing.group(1)!} /* Embed Foundation Extensions */');
      return existing.group(1)!;
    }

    final id = _id();
    _insertObject(
      'PBXCopyFilesBuildPhase',
      '''
\t\t$id /* Embed Foundation Extensions */ = {
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
''',
    );
    _appendListEntry(
        runnerTargetId, 'buildPhases', '$id /* Embed Foundation Extensions */');
    return id;
  }

  void _addBuildFile(String id, String comment, String fields) {
    _insertObject(
      'PBXBuildFile',
      '\t\t$id /* $comment */ = {isa = PBXBuildFile; $fields };\n',
    );
  }

  void _addFileReference(String id, String comment, String fields) {
    _insertObject(
      'PBXFileReference',
      '\t\t$id /* $comment */ = {isa = PBXFileReference; $fields };\n',
    );
  }

  void _addGroup(String id, String comment, List<String> children,
      {String? path}) {
    _insertObject(
      'PBXGroup',
      '''
\t\t$id /* $comment */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
${children.map((child) => '\t\t\t\t$child,').join('\n')}
\t\t\t);
${path == null ? '' : '\t\t\tpath = $path;\n'}\t\t\tsourceTree = "<group>";
\t\t};
''',
    );
  }

  void _addFrameworksPhase(String id, List<String> files) {
    _insertObject(
      'PBXFrameworksBuildPhase',
      '''
\t\t$id /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
${files.map((file) => '\t\t\t\t$file,').join('\n')}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
''',
    );
  }

  void _addSourcesPhase(String id, List<String> files) {
    _insertObject(
      'PBXSourcesBuildPhase',
      '''
\t\t$id /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
${files.map((file) => '\t\t\t\t$file,').join('\n')}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
''',
    );
  }

  void _addResourcesPhase(String id) {
    _insertObject(
      'PBXResourcesBuildPhase',
      '''
\t\t$id /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
''',
    );
  }

  void _addNativeTarget(
    String id,
    String configListId,
    String sourcesId,
    String frameworksId,
    String resourcesId,
    String productFileId,
    String supportProductId,
  ) {
    _insertObject(
      'PBXNativeTarget',
      '''
\t\t$id /* $tunnelTargetName */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = $configListId /* Build configuration list for PBXNativeTarget "$tunnelTargetName" */;
\t\t\tbuildPhases = (
\t\t\t\t$sourcesId /* Sources */,
\t\t\t\t$frameworksId /* Frameworks */,
\t\t\t\t$resourcesId /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = $tunnelTargetName;
\t\t\tpackageProductDependencies = (
\t\t\t\t$supportProductId /* $tunnelProductName */,
\t\t\t);
\t\t\tproductName = $tunnelTargetName;
\t\t\tproductReference = $productFileId /* $tunnelTargetName.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t};
''',
    );
  }

  void _addBuildConfigurationList(
    String listId,
    String owner,
    String bundleId,
    String deploymentTarget,
    String? teamId,
  ) {
    final debugId = _id();
    final releaseId = _id();
    final profileId = _id();
    for (final entry in [
      ('Debug', debugId),
      ('Release', releaseId),
      ('Profile', profileId),
    ]) {
      _insertObject(
        'XCBuildConfiguration',
        _tunnelBuildConfiguration(
          id: entry.$2,
          name: entry.$1,
          bundleId: bundleId,
          deploymentTarget: deploymentTarget,
          teamId: teamId,
        ),
      );
    }
    _insertObject(
      'XCConfigurationList',
      '''
\t\t$listId /* Build configuration list for $owner */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t$debugId /* Debug */,
\t\t\t\t$releaseId /* Release */,
\t\t\t\t$profileId /* Profile */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
''',
    );
  }

  String _tunnelBuildConfiguration({
    required String id,
    required String name,
    required String bundleId,
    required String deploymentTarget,
    required String? teamId,
  }) {
    final isDebug = name == 'Debug';
    return '''
\t\t$id /* $name */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = $tunnelTargetName/$tunnelTargetName.entitlements;
\t\t\t\t"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = "\$(FLUTTER_BUILD_NUMBER)";
${teamId == null ? '' : '\t\t\t\tDEVELOPMENT_TEAM = $teamId;\n'}\t\t\t\tENABLE_APP_SANDBOX = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = $tunnelTargetName/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = $tunnelTargetName;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"\$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t\t"@executable_path/../../../../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = $deploymentTarget;
\t\t\t\tMARKETING_VERSION = "\$(FLUTTER_BUILD_NAME)";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = $bundleId.$tunnelTargetName;
\t\t\t\tPRODUCT_NAME = "\$(TARGET_NAME)";
\t\t\t\tREGISTER_APP_GROUPS = YES;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
${isDebug ? '\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";\n' : ''}\t\t\t};
\t\t\tname = $name;
\t\t};
''';
  }

  void _ensureTargetAttributes(String projectId, String targetId) {
    final block = _objectBlock(projectId);
    if (block.text.contains('$targetId = {')) return;
    final index = text.indexOf('TargetAttributes = {', block.start);
    if (index < 0 || index > block.end) return;
    final insert = text.indexOf('\n', index) + 1;
    text = text.replaceRange(insert, insert, '''
\t\t\t\t\t$targetId = {
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t\tProvisioningStyle = Automatic;
\t\t\t\t\t};
''');
  }

  void _patchRunnerBuildSettings(
    String bundleId,
    String groupId,
    String deploymentTarget,
    String? teamId,
  ) {
    final runnerConfigListId = _requiredMatchIn(
      _objectBlock(_targetId('Runner')!).text,
      RegExp(r'buildConfigurationList = ([A-Z0-9]{24}) /\*'),
      'Runner build configuration list',
    );
    for (final configId in _configurationIds(runnerConfigListId)) {
      _setBuildSetting(configId, 'PRODUCT_BUNDLE_IDENTIFIER', bundleId);
      _setBuildSetting(configId, 'MACOSX_DEPLOYMENT_TARGET', deploymentTarget);
      _setBuildSetting(configId, 'REGISTER_APP_GROUPS', 'YES');
      if (teamId != null) {
        _setBuildSetting(configId, 'DEVELOPMENT_TEAM', teamId);
      }
    }
  }

  void _patchAllMacOSDeploymentTargets(String deploymentTarget) {
    text = text.replaceAllMapped(
      RegExp(r'MACOSX_DEPLOYMENT_TARGET = [^;]+;'),
      (_) => 'MACOSX_DEPLOYMENT_TARGET = $deploymentTarget;',
    );
  }

  void _patchTunnelBuildSettings(
    String bundleId,
    String deploymentTarget,
    String? teamId,
  ) {
    final targetId = _targetId(tunnelTargetName)!;
    final configListId = _requiredMatchIn(
      _objectBlock(targetId).text,
      RegExp(r'buildConfigurationList = ([A-Z0-9]{24}) /\*'),
      'XrayTunnel build configuration list',
    );
    for (final configId in _configurationIds(configListId)) {
      _setBuildSetting(
        configId,
        'CODE_SIGN_ENTITLEMENTS',
        '$tunnelTargetName/$tunnelTargetName.entitlements',
      );
      _setBuildSetting(
          configId, 'PRODUCT_BUNDLE_IDENTIFIER', '$bundleId.$tunnelTargetName');
      _setBuildSetting(configId, 'MACOSX_DEPLOYMENT_TARGET', deploymentTarget);
      _setBuildSetting(
          configId, 'CURRENT_PROJECT_VERSION', r'"$(FLUTTER_BUILD_NUMBER)"');
      _setBuildSetting(
          configId, 'MARKETING_VERSION', r'"$(FLUTTER_BUILD_NAME)"');
      _setBuildSetting(configId, 'REGISTER_APP_GROUPS', 'YES');
      _setBuildSetting(configId, 'SKIP_INSTALL', 'YES');
      if (teamId != null) {
        _setBuildSetting(configId, 'DEVELOPMENT_TEAM', teamId);
      }
    }
  }

  List<String> _configurationIds(String configListId) {
    final block = _objectBlock(configListId).text;
    return RegExp(r'([A-Z0-9]{24}) /\* (Debug|Release|Profile) \*/')
        .allMatches(block)
        .map((match) => match.group(1)!)
        .toList();
  }

  void _setBuildSetting(String configId, String key, String value) {
    final block = _objectBlock(configId);
    final keyPattern =
        RegExp('(^\\s*)"?${RegExp.escape(key)}"? = [^;]+;', multiLine: true);
    final match = keyPattern.firstMatch(block.text);
    if (match != null) {
      final replacement = '${match.group(1)}$key = $value;';
      text = text.replaceRange(
          block.start + match.start, block.start + match.end, replacement);
      return;
    }

    final settingsIndex = text.indexOf('buildSettings = {', block.start);
    final insert = text.indexOf('\n', settingsIndex) + 1;
    text = text.replaceRange(insert, insert, '\t\t\t\t$key = $value;\n');
  }

  void _removeFrameworkFromTarget(String targetId, String frameworkName) {
    final targetBlock = _objectBlock(targetId).text;
    final frameworksIdMatch =
        RegExp(r'([A-Z0-9]{24}) /\* Frameworks \*/').firstMatch(targetBlock);
    if (frameworksIdMatch == null) return;
    final frameworksId = frameworksIdMatch.group(1)!;
    final frameworksBlock = _objectBlock(frameworksId);
    final line = RegExp(
      '^\\s*[A-Z0-9]{24} /\\* ${RegExp.escape(frameworkName)}(?: in Frameworks)? \\*/,\\n',
      multiLine: true,
    ).firstMatch(frameworksBlock.text);
    if (line == null) return;
    text = text.replaceRange(
      frameworksBlock.start + line.start,
      frameworksBlock.start + line.end,
      '',
    );
  }

  void _removeProjectFileReferences(String fileName) {
    final ids = <String>{};
    for (final match in RegExp(
      '([A-Z0-9]{24}) /\\* ${RegExp.escape(fileName)}(?: in Frameworks)? \\*/ = \\{[^\\n]*?;',
    ).allMatches(text)) {
      ids.add(match.group(1)!);
    }
    for (final id in ids) {
      text = text.replaceAll(
        RegExp('^\\s*$id /\\* [^\\n]*? \\*/ = \\{[^\\n]*?;\\n',
            multiLine: true),
        '',
      );
      text = text.replaceAll(
        RegExp('^\\s*$id /\\* [^\\n]*? \\*/,\\n', multiLine: true),
        '',
      );
    }
  }

  void _appendListEntry(String objectId, String listName, String entry) {
    final block = _objectBlock(objectId);
    if (block.text.contains(entry.split(' /* ').first)) return;

    final listStart = text.indexOf('$listName = (', block.start);
    if (listStart < 0 || listStart > block.end) return;
    final close = text.indexOf('\n\t\t\t);', listStart);
    if (close < 0 || close > block.end) return;
    text = text.replaceRange(close, close, '\n\t\t\t\t$entry,');
  }

  void _insertObject(String sectionName, String objectText) {
    final end = text.indexOf('/* End $sectionName section */');
    if (end < 0) {
      final objectsStart = text.indexOf('objects = {');
      final insert = text.indexOf('\n', objectsStart) + 1;
      text = text.replaceRange(insert, insert,
          '\n/* Begin $sectionName section */\n$objectText/* End $sectionName section */\n');
      return;
    }
    text = text.replaceRange(end, end, objectText);
  }

  String? _targetId(String name) {
    final pattern = RegExp(
      '([A-Z0-9]{24}) /\\* ${RegExp.escape(name)} \\*/ = \\{\\s*isa = PBXNativeTarget;',
      multiLine: true,
    );
    return pattern.firstMatch(text)?.group(1);
  }

  _Block _objectBlock(String id) {
    final start = text.indexOf('\t\t$id ');
    if (start < 0) _fail('Could not find Xcode object $id.');
    var brace = text.indexOf('{', start);
    var depth = 0;
    for (var i = brace; i < text.length; i++) {
      final char = text.codeUnitAt(i);
      if (char == 123) depth++;
      if (char == 125) {
        depth--;
        if (depth == 0) {
          final end = text.indexOf(';\n', i) + 2;
          return _Block(start, end, text.substring(start, end));
        }
      }
    }
    _fail('Could not parse Xcode object $id.');
  }

  String _requiredMatch(RegExp pattern, String description) {
    final match = pattern.firstMatch(text);
    if (match == null) _fail('Could not find $description in project.pbxproj.');
    return match.group(1)!;
  }

  String _requiredMatchIn(String source, RegExp pattern, String description) {
    final match = pattern.firstMatch(source);
    if (match == null) _fail('Could not find $description in project.pbxproj.');
    return match.group(1)!;
  }

  String _id() {
    const chars = '0123456789ABCDEF';
    while (true) {
      final id = List.generate(24, (_) => chars[_random.nextInt(16)]).join();
      if (!text.contains(id)) return id;
    }
  }
}

class _Block {
  const _Block(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

class _Options {
  const _Options({
    required this.projectDir,
    required this.deploymentTarget,
    required this.bundleId,
    required this.groupId,
    required this.teamId,
    required this.help,
  });

  final String projectDir;
  final String deploymentTarget;
  final String? bundleId;
  final String? groupId;
  final String? teamId;
  final bool help;

  static _Options parse(List<String> args) {
    final values = <String, String>{};
    var help = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--help' || arg == '-h') {
        help = true;
        continue;
      }
      if (!arg.startsWith('--')) {
        _fail('Unknown argument: $arg');
      }
      final equals = arg.indexOf('=');
      if (equals > 0) {
        values[arg.substring(2, equals)] = arg.substring(equals + 1);
        continue;
      }
      if (i + 1 >= args.length) {
        _fail('Missing value for $arg');
      }
      values[arg.substring(2)] = args[++i];
    }

    return _Options(
      projectDir: values['project-dir'] ?? '.',
      deploymentTarget: values['deployment-target'] ?? '13.0',
      bundleId: values['bundle-id'],
      groupId: values['group-id'],
      teamId: values['team-id'],
      help: help,
    );
  }
}

Never _fail(String message) {
  stderr.writeln('setup_macos_vpn: $message');
  exit(64);
}
