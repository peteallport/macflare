# macflare

Power tools for Cloudflare natively on macOS.

## ❤️ Support macflare

- [ ] **COMING SOON**: Download from the App Store to support new features, enhancements, and for automatic updates.
- [x] Know a really cool company hiring? [I'm a really cool guy](https://peteallport.com).
- [x] Have deep pockets? Consider [sponsoring macflare](https://github.com/sponsors/peteallport).

## 🧑‍💻 Local development

- Open `macflare.xcodeproj` in Xcode 16.4+
- Copy `macflare/Config/Development.example.xcconfig` to `macflare/Config/Development.xcconfig` and set your values (see `macflare/Config/README.md`).
- To build from CLI without signing: `xcodebuild -project macflare.xcodeproj -scheme macflare -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`

## 📄 License

This project is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/).

You’re free to use, modify, and share the code for non-commercial purposes with attribution.  
Commercial use requires explicit permission from the author.
