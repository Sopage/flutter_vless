import 'dart:io';

import 'package:flutter_vless/url/vless.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/xray_config_probe.dart <vless-url>');
    exitCode = 64;
    return;
  }

  // Small local probe used during device debugging: paste a VLESS URL and
  // inspect the exact Xray JSON before it is handed to NetworkExtension.
  stdout.write(VlessURL(url: args.first).getFullConfiguration());
}
