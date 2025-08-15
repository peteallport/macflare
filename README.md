# macflare

Power tools for Cloudflare natively on macOS.

## 🚀 Getting Started

1. Clone the repository
2. Open `macflare.xcodeproj` in Xcode
3. Select your team in Signing & Capabilities
4. Build and run!

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed setup instructions.

## ❤️ Support macflare

- [ ] **COMING SOON**: Download from the App Store to support new features, enhancements, and for automatic updates.
- [x] Know a really cool company hiring? [I'm a really cool guy](https://peteallport.com).
- [x] Have deep pockets? Consider [sponsoring macflare](https://github.com/sponsors/peteallport).

## 🔥 Hot Reload Development

macflare supports blazing-fast hot reload for SwiftUI development using the [Inject](https://github.com/krzysztofzablocki/Inject) package.

### ✅ Quick Setup

1. **Download InjectionIII.app** from [GitHub Releases](https://github.com/johnno1962/InjectionIII/releases)
2. **Launch InjectionIII.app** and open your `macflare.xcodeproj`
3. **Run your app** in Xcode (Debug mode)
4. **Make changes** to any SwiftUI view and save (⌘+S)
5. **Watch changes appear instantly** in your running app! 🎉

### 🛠️ Configuration Status

✅ **Inject package v1.5.2** - Already integrated and linked  
✅ **Build settings** - `-Xlinker -interposable` and `EMIT_FRONTEND_COMMAND_LINES = YES` configured  
✅ **Entitlements** - Hot reload permissions added  
✅ **SwiftUI integration** - Views configured with `@Inject.ObserveInjection` and `.enableInjection()`

Save and watch it update instantly!

## 🧑‍💻 Local development

- Open `macflare.xcodeproj` in Xcode 15+ or later.
- To build from the CLI without code signing:  
  `xcodebuild -project macflare.xcodeproj -scheme macflare -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
- To run tests from the CLI:  
  `xcodebuild -project macflare.xcodeproj -scheme macflare -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`
- See [CONTRIBUTING.md](CONTRIBUTING.md) for development standards and pull-request guidelines.

### Git hooks

- Run once per clone to enable repo hooks:
  ```bash
  git config core.hooksPath .githooks
  ```

## 📄 License

This project is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/).

You’re free to use, modify, and share the code for non-commercial purposes with attribution.  
Commercial use requires explicit permission from the author.
