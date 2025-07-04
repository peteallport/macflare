# Hot Reloading with HotSwiftUI

This project is configured with [HotSwiftUI](https://github.com/johnno1962/HotSwiftUI) for hot reloading during development. This allows you to see changes instantly without rebuilding the entire app.

## ✅ Complete Setup (Ready to Use!)

### 1. **HotSwiftUI Package**
- Added to project as Swift Package dependency
- Much more reliable than InjectionIII - no external apps needed!

### 2. **Project Configuration**
- **Global Import**: `@_exported import HotSwiftUI` in `macflareApp.swift`
- **Linker Flags**: `-Xlinker -interposable` added to Debug configuration
- **Sandbox Disabled**: App sandbox disabled for Debug builds to allow hot reloading

### 3. **View Support**
- Both `WelcomeView` and `ContentView` have hot reloading enabled
- Each view has `@ObserveInjection var redraw` and `.eraseToAnyView()`

## 🚀 How to Use Hot Reloading

### **Step 1: Build & Run**
1. Open `macflare.xcodeproj` in Xcode
2. Select **Debug** configuration (not Release)
3. Build and run (⌘+R) on macOS or Simulator

### **Step 2: Test Hot Reloading**
1. **Keep the app running**
2. **Open** `WelcomeView.swift` in Xcode
3. **Change line 48**: `"🔥 Test Hot Reload!"` → `"✨ IT WORKS!"`
4. **Save the file** (⌘+S)
5. **Watch your running app update instantly!** 🎉

### **Step 3: Try More Changes**
- Change button colors: `.buttonStyle(.borderedProminent)` → `.buttonStyle(.bordered)`
- Change text: `"Macflare"` → `"Macflare 🚀"`
- Add spacing: `VStack(spacing: 40)` → `VStack(spacing: 60)`

## 🎯 Key Advantages of HotSwiftUI

| Feature | HotSwiftUI | InjectionIII |
|---------|------------|-------------|
| **External App** | ✅ Self-contained | ❌ Required InjectionIII.app |
| **Configuration** | ✅ Works out of the box | ❌ Manual setup needed |
| **Reliability** | ✅ Very reliable | ❌ Connection issues |
| **Setup** | ✅ Simple package import | ❌ Complex configuration |

## 🔍 Troubleshooting

### **If Hot Reloading Doesn't Work:**

1. **Check Console**: Look for HotSwiftUI logs in Xcode console
2. **Verify Debug Mode**: Ensure you're running Debug, not Release
3. **Clean Build**: Product → Clean Build Folder, then rebuild
4. **Restart App**: Sometimes needs a fresh start

### **Common Issues:**
- **No updates visible**: Check that Debug configuration is active
- **App crashes**: Ensure linker flags are properly set
- **Build errors**: Try cleaning build folder and rebuilding

## 🎯 Best Practices

### **Adding Hot Reloading to New Views:**
```swift
struct MyNewView: View {
    @ObserveInjection var redraw  // Add this
    
    var body: some View {
        VStack {
            Text("Hello, World!")
        }
        .eraseToAnyView()  // Add this
    }
}
```

### **Performance Notes:**
- Only enabled in Debug builds
- No performance impact in Release builds
- Sandbox disabled only affects Debug builds

## 🛡️ Security

- **App Sandbox**: Disabled only for Debug builds
- **Release builds**: Maintain full sandbox protection
- **Development only**: Hot reloading never affects production

---

## 📝 What Changed from InjectionIII

✅ **Switched to HotSwiftUI** - much more reliable
✅ **Self-contained** - no external app required
✅ **Better syntax** - `@ObserveInjection` + `.eraseToAnyView()`
✅ **Easier setup** - works immediately after package import

**Current Status: ✅ Ready to use!**

Try changing the button text now and see the magic happen! 🪄