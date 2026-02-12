This recreates the famous title card from "The Thing" (1982) using Metal.

macOS 26.2
Xcode 26.2
Apple metal version 32023.850

Besides Xcode and Xcode Developer Tools you may need to install Metal. To check:

```
> xcrun metal -v
Apple metal version 32023.850 (metalfe-32023.850.10)
Target: air64-apple-darwin25.2.0
Thread model: posix
InstalledDir: /Volumes/MetalToolchainCryptex/Metal.xctoolchain/usr/metal/current/bin
```

If you don't see this, then do:

```
xcodebuild -downloadComponent MetalToolchain
xcrun -k
xcrun metal -v # Should work now
```

Then to start the app and see the logo:

```
make run
```
