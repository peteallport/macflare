# Contributing to macflare

## Development Setup

### Prerequisites

- Xcode 15.0+
- Apple Developer Account (for signing)
- macOS 14.0+

### Getting Started

1. **Clone the repository**

   ```bash
   git clone https://github.com/yourusername/macflare.git
   cd macflare
   ```

2. **Set up signing in Xcode**

   - Open `macflare.xcodeproj` in Xcode
   - Select the project in the navigator
   - Go to the "Signing & Capabilities" tab
   - Select your team from the "Team" dropdown
   - Xcode will automatically update the bundle identifier and provisioning

3. **Build and run**
   - The project uses automatic signing
   - No additional configuration needed

## How Signing Works

This project uses **automatic signing** with a **pre-commit hook** that cleans sensitive information:

- **Locally**: You work with your actual team ID and bundle identifier
- **In Git**: Only clean, generic versions are committed
- **For Others**: Contributors set their own team ID in Xcode normally

### Pre-commit Hook

The repository includes a pre-commit hook that automatically:

- Blocks any `.p12` or `.mobileprovision` files from being committed
- Cleans development team IDs and bundle identifiers from `project.pbxproj`
- Ensures no sensitive signing information enters the repository

This means you can work normally with automatic signing while keeping the repository secure for public distribution.

## Project Structure

```
macflare/
├── Model/          # Data models
├── View/           # SwiftUI views
├── Assets.xcassets # App icons and images
└── ...
```

## License

This project is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/).
