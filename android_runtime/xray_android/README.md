# Xray Android Runtime

This Android library packages the native Xray runtime used by `flutter_vless_android`.

Maven coordinates:

```text
dev.tfox.fluttervless:xray-android:26.6.1
```

The AAR contains Android ARM native libraries and Xray geodata assets:

- `jni/arm64-v8a/libxray.so`
- `jni/arm64-v8a/libtun2socks.so`
- `jni/armeabi-v7a/libxray.so`
- `jni/armeabi-v7a/libtun2socks.so`
- `assets/geoip.dat`
- `assets/geosite.dat`

Build a local Maven repo before publishing or testing the Android wrapper locally:

```bash
tool/build_android_runtime_maven.sh
```

Publish to Maven Central after the `dev.tfox` namespace, Central Portal token, and GPG signing key are configured:

```bash
tool/publish_android_runtime_maven.sh
```

Required environment variables for Maven Central upload:

```text
MAVEN_CENTRAL_USERNAME
MAVEN_CENTRAL_PASSWORD
SIGNING_IN_MEMORY_KEY
SIGNING_IN_MEMORY_KEY_PASSWORD
SIGNING_IN_MEMORY_KEY_ID
```

`SIGNING_IN_MEMORY_KEY_ID` is optional for local shell usage, but keeping it in GitHub Secrets makes CI signing explicit.

Central Portal setup:

1. Register the namespace `dev.tfox`, not `dev.tfox.flutter_vless`.
2. Add the DNS TXT record requested by Central Portal to `tfox.dev`.
3. Generate a Central Portal user token.
4. Store the token username/password and signing key values as GitHub Secrets in the `maven-central` environment.

The Maven `groupId` used by this project is `dev.tfox.fluttervless`. It is valid after the parent `dev.tfox` namespace is verified.

When Xray is updated:

1. Rebuild Android `libxray.so` files in `packages/flutter_vless_android/android/src/main/jniLibs`.
2. Keep `geoip.dat` and `geosite.dat` in `packages/flutter_vless_android/android/src/main/assets`.
3. Set `XRAY_RUNTIME_VERSION` to the new Maven artifact version without the leading `v`.
4. Run `tool/build_android_runtime_maven.sh` and verify the example against the local Maven repo.
5. Run `tool/publish_android_runtime_maven.sh` or the `Publish Android Runtime AAR` GitHub workflow.
6. Publish `flutter_vless_android` to Pub.dev after the Maven artifact is visible on Maven Central.
