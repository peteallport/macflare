# Development Configuration

## Setup for New Contributors

1. Copy `Development.example.xcconfig` to `Development.xcconfig`
2. Edit `Development.xcconfig` with your own values:
   - Replace `YOUR_TEAM_ID_HERE` with your Apple Developer Team ID
   - Replace `com.yourcompany` with your bundle identifier prefix

## Why This Setup?

- `Development.xcconfig` contains personal signing information (not committed to git)
- `Development.example.xcconfig` is a template for new contributors (committed to git)
- This allows everyone to have their own signing configuration while sharing the same codebase

## Finding Your Team ID

1. Open Xcode
2. Go to Preferences > Accounts
3. Select your Apple ID
4. Your Team ID appears next to your team name
