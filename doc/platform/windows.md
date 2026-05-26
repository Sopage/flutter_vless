# Windows

Windows uses a local Xray-backed path with system routing and proxy behavior.

## Quick Run The Example

Place `xray.exe` in the example before running Windows:

```text
example/windows/xray/xray.exe
```

Then run:

```bash
cd example
flutter pub get
flutter run -d windows
```

## What You Need

- a recent Xray release available locally as `xray.exe`
- a Windows project with the plugin configured
- enough permissions for system-level routing changes when using tunnel mode

## Suggested Placement

Keep `xray.exe` where the plugin can discover it from the app or example project.

For the bundled example, the expected structure is:

```text
example/
  windows/
    xray/
      xray.exe
```

For your own app, mirror that structure under your app's Windows directory or
use one of the plugin's supported lookup locations.

## Runtime Notes

- proxy-only mode is the lighter path
- VPN/tunnel mode may require elevated permissions
- confirm your app ships the assets or binaries that the Windows backend expects

## Common Pitfalls

- missing `xray.exe`
- assuming the Windows backend will download core binaries for you
- using the wrong mode for the behavior you are testing
