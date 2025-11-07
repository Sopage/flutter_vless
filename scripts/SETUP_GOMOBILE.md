# Setting Up gomobile for XRay Framework Building

If you encounter errors like "unable to import bind: no Go package in golang.org/x/mobile/bind", follow these steps:

## Manual Setup

1. **Install gomobile and gobind:**
   ```bash
   go install golang.org/x/mobile/cmd/gomobile@latest
   go install golang.org/x/mobile/cmd/gobind@latest
   ```

2. **Add Go bin to PATH:**
   ```bash
   export PATH=$(go env GOPATH)/bin:$PATH
   # Add this to your ~/.zshrc or ~/.bash_profile for persistence
   ```

3. **Initialize gomobile:**
   ```bash
   gomobile init
   ```

4. **Verify installation:**
   ```bash
   gomobile version
   gobind -h
   ```

## Troubleshooting

### If gomobile init fails:

Try downloading dependencies manually:
```bash
# Create a temp module
mkdir -p /tmp/gomobile-setup
cd /tmp/gomobile-setup
go mod init temp-setup

# Download mobile package
go get golang.org/x/mobile@latest

# Try init again
gomobile init
```

### If network issues occur:

Set Go proxy to direct:
```bash
export GOPROXY=direct
gomobile init
```

### Verify gomobile directory:

Check if gomobile directory exists:
```bash
ls -la ~/gomobile
# or
ls -la $(go env GOPATH)/gomobile
```

If it doesn't exist, create it:
```bash
mkdir -p $(go env GOPATH)/gomobile
export GOMOBILE=$(go env GOPATH)/gomobile
gomobile init
```

## Alternative: Use Pre-built Framework

If building continues to fail, you can:
1. Use a pre-built XRay framework from the iOS example
2. Manually build using Xcode if you have the source
3. Contact the xray-mobile repository maintainer for pre-built frameworks

