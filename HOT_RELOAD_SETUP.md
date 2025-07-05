# 🔥 Hot Reload Setup Guide for macflare

This guide will help you set up hot reload support using the [Inject](https://github.com/krzysztofzablocki/Inject) package for blazing-fast SwiftUI development.

## ✅ Prerequisites

### 1. Install InjectionIII.app
- Download the latest release from [InjectionIII GitHub Releases](https://github.com/johnno1962/InjectionIII/releases)
- Extract and move `InjectionIII.app` to your `/Applications` folder
- Launch the app at least once to register it with macOS

### 2. Add Inject Swift Package
Add the Inject package to your Xcode project:

**Via Xcode:**
1. Open your project in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter: `https://github.com/krzysztofzablocki/Inject.git`
4. Click **Add Package**
5. Add the `Inject` product to your main app target

**Via Swift Package Manager:**
```swift
dependencies: [
    .package(url: "https://github.com/krzysztofzablocki/Inject.git", from: "1.5.0")
]
```

## ⚙️ Project Configuration (Already Done)

The following configurations have already been applied to your project:

### Build Settings
- ✅ Added `-Xlinker -interposable` to "Other Linker Flags" for Debug builds on macOS
- ✅ This enables the dynamic loading of new code implementations

### Entitlements
- ✅ Added `com.apple.security.cs.disable-library-validation` to allow injection
- ✅ This permits loading of dynamically injected code

### SwiftUI Views
- ✅ Added `@_exported import Inject` to main app file for global availability
- ✅ Added `@ObserveInjection var inject` to SwiftUI views
- ✅ Added `.enableInjection()` to view bodies

## 🚀 Usage Instructions

### 1. Configure InjectionIII App
1. Launch `InjectionIII.app` from your Applications folder
2. From the menu bar, select **File → Open Project**
3. Navigate to your project and select the `macflare.xcodeproj` file
4. You should see a notification that the project is being watched

### 2. Launch Your App
1. Build and run your macOS app in Xcode (Debug configuration)
2. Look for console messages like:
   ```
   💉 InjectionIII connected /path/to/your/macflare.xcodeproj
   💉 Watching files under /path/to/your/project
   ```

### 3. Start Hot Reloading! 🎉
1. Make changes to any SwiftUI view file
2. Save the file (⌘+S)
3. Watch your changes appear instantly in the running app!

## 🎨 Optional: Configure Hot Reload Animation

Add this to your app's initialization to see smooth transitions when code is injected:

```swift
// In your App file or main view
init() {
    InjectConfiguration.animation = .easeInOut(duration: 0.3)
}
```

## 📝 What Views Are Ready for Hot Reload

The following views have been configured for hot reload:

- ✅ `WelcomeView` - Main welcome screen
- ✅ `ContentView` - Navigation and data management view

## 🔧 Troubleshooting

### App Not Connecting
- Ensure InjectionIII.app is running
- Check that your project is correctly selected in InjectionIII
- Verify console output for connection messages

### Injection Not Working
- Ensure you're running a Debug build
- Check that the `-Xlinker -interposable` flag is set for Debug builds
- Verify the entitlements are properly configured

### Permission Issues
- macOS may prompt for permission to allow network connections
- Allow InjectionIII to access your files and network

## 🚨 Important Notes

### Production Safety
- Hot reload is **automatically disabled** in Release builds
- The Inject code becomes a no-op and gets stripped by the compiler
- No need to remove injection code before shipping

### Performance
- Hot reload only works in Debug builds
- There's no performance impact on Release builds
- Changes are typically reflected within 1-2 seconds

### Limitations
- Only function/method implementations can be hot-reloaded
- Cannot change view initializers or struct definitions
- State is preserved between hot reloads

## 📚 Further Reading

- [Inject Package Documentation](https://github.com/krzysztofzablocki/Inject)
- [InjectionIII Documentation](https://github.com/johnno1962/InjectionIII)
- [Hot Reloading Best Practices](https://www.merowing.info/hot-reloading-in-swift/)

---

**Happy Hot Reloading! 🔥**

*This setup saves hours of development time by eliminating the need to rebuild and restart your app for every UI change.*