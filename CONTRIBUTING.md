# Contributing to macflare

## Development Setup

### Prerequisites

- Xcode 15.0+
- An Apple Developer Account (for signing)
- macOS 14.0+

### Getting Started

1. **Clone the macflare repository**

   ```bash
   git clone https://github.com/peteallport/macflare.git
   cd macflare
   ```

2. **Important: enable hooks once after cloning**:

   ```bash
   git config core.hooksPath .githooks
   ```

3. **Set up signing in Xcode**

   - Open `macflare.xcodeproj` in Xcode
   - Select the project in the navigator
   - Go to the "Signing & Capabilities" tab
   - Select your team from the "Team" dropdown
   - Xcode will automatically update the bundle identifier and provisioning

4. **🔥 Hot Reload Development**: macflare supports blazing-fast hot reload for SwiftUI development outside of Xcode in editors like Cursor or VS Code using the [Inject](https://github.com/krzysztofzablocki/Inject) package.

- **Download InjectionIII.app** from [GitHub Releases](https://github.com/johnno1962/InjectionIII/releases)
- **Launch InjectionIII.app** and open your `macflare.xcodeproj`
- **Run your app** in Xcode (Debug mode)
- **Make changes** to any SwiftUI view and save (⌘+S)
- **Watch changes appear instantly** in your running app! 🎉

5. **Set up SweetPad Autocomplete (Optional)**: For enhanced autocomplete in editors like Cursor or VS Code, install the [SweetPad extension](https://sweetpad.hyzyla.dev/docs/autocomplete/) and run `brew install xcode-build-server --head`, then use the "SweetPad: Generate Build Server Config" command to create a local `buildServer.json` file.

6. **Build and run**
   - The project uses automatic signing
   - No additional configuration needed

### How Signing Works

This project uses **automatic signing** with a **pre-commit hook** that cleans sensitive information:

- **Locally**: You work with your actual team ID and bundle identifier
- **In Git**: Only clean, generic versions are committed
- **For Others**: Contributors set their own team ID in Xcode normally

#### Pre-commit Hook

The repository includes a pre-commit hook that automatically:

- Blocks any `.p12` or `.mobileprovision` files from being committed.
- Cleans development team IDs and bundle identifiers from `project.pbxproj`.
- Endeavors to prevent sensitive signing information enters the public repository.

This means you can work normally with automatic signing while keeping the repository secure for public contributions.

# Contributing

Thanks for your interest in improving `macflare`!

### Project Structure

```
macflare/
├── Model/          # Data models
├── View/           # SwiftUI views
├── Assets.xcassets # App icons and images
└── etc.
```

### License

This project is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). Free to use for non-commercial use.

### Pull requests

- Include a clear summary and testing steps (see PR template).
- Prefer small, focused changes.
- Add/adjust tests when possible.

### Code style

- Swift types use UpperCamelCase (e.g., `MacflareApp`).
- Keep functions small and compose with SwiftUI where possible.
