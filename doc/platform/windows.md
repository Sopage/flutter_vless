# Windows

Windows uses a local Xray-backed path with system routing and proxy behavior.

## What You Need

- a recent Xray release available locally as `xray.exe`
- a Windows project with the plugin configured
- enough permissions for system-level routing changes when using tunnel mode

## Suggested Placement

Keep `xray.exe` where the plugin can discover it from the app or example project.

## Runtime Notes

- proxy-only mode is the lighter path
- VPN/tunnel mode may require elevated permissions
- confirm your app ships the assets or binaries that the Windows backend expects

## Common Pitfalls

- missing `xray.exe`
- assuming the Windows backend will download core binaries for you
- using the wrong mode for the behavior you are testing
