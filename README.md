<p align="center">
  <img src="./Foqos/Assets.xcassets/AppIcon.appiconset/AppIcon~ios-marketing.png" width="250" style="border-radius: 40px;">
</p>

<p align="center">
<a href="https://www.buymeacoffee.com/ambitionsoftware" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/arial-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
</p>

<h1 align="center"><a href="https://apps.apple.com/ca/app/foqos/id6736793117">Foqos</a></h1>

<p align="center">
  <strong>Focus through physical blocking</strong>
</p>

<p align="center">
  Foqos allows you to lock distracting apps behind the tap of an NFC tag, helping you stay focused and build better digital habits. Free and open source alternative to Brick, Bloom, Unpluq, Blok and more!
</p>

---

## ✨ Features

- **🏷️ NFC & QR Blocking**: Use NFC tags or QR codes to start and stop blocking sessions
- **🧩 Multiple Strategies**: Manual, NFC, QR, NFC + Manual, QR + Manual
- **🔐 Physical Unblock**: Optionally require a specific NFC tag or QR code to stop blocking
- **📱 Customizable Profiles**: Create multiple blocking profiles for different scenarios (work, study, sleep, etc.)
- **📊 Habit Tracking**: Visual tracking of your blocked sessions to monitor your focus habits
- **⏸️ Break Functionality**: Take breaks during blocking sessions when needed
- **🔄 Live Activities**: Real-time updates on your Lock Screen showing blocking status

## 📋 Requirements

- iOS 16.0+
- iPhone with NFC capability
- Screen Time permissions (for app blocking functionality)

## 🚀 Getting Started

### From the App Store

1. Download Foqos from the [App Store](https://apps.apple.com/ca/app/foqos/id6736793117)
2. Grant Screen Time permissions when prompted
3. Create your first blocking profile
4. Set up your NFC tags and start focusing!

### Setting Up NFC Tags

1. Purchase NFC tags (NTAG213 or similar recommended)
2. In Foqos, create a blocking profile
3. Use the NFC writing feature to program your tags
4. Place tags in strategic locations (desk, study area, etc.)
5. Tap to start/stop blocking sessions

## 🛠️ Development

### Prerequisites

- Xcode 15.0+
- iOS 17.0+ SDK
- Swift 5.9+
- Apple Developer Account (for Screen Time and NFC entitlements)

### Building the Project

```bash
git clone https://github.com/awaseem/foqos.git
cd foqos
open foqos.xcodeproj
```

### Project Structure

```
foqos/
├── Foqos/                     # Main app target
│   ├── Views/                 # SwiftUI views
│   ├── Models/                # Data models
│   │   └── Strategies/        # Blocking strategies
│   ├── Components/            # Reusable UI components
│   ├── Utils/                 # Utility functions
│   └── Intents/               # App Intents & Shortcuts
├── FoqosWidget/               # Widget extension
└── FoqosDeviceMonitor/        # Device monitoring extension
```

### Key Technologies Used

- **SwiftUI** - Modern declarative UI framework
- **SwiftData** - Local data persistence
- **Family Controls** - App blocking functionality
- **Core NFC** - NFC tag reading/writing
- **CodeScanner** - QR code scanning
- **BackgroundTasks** - Background processing
- **Live Activities** - Dynamic Island and Lock Screen updates
- **WidgetKit** - Home Screen widgets
- **App Intents** - Shortcuts and automation support

## 🔒 Blocking Strategies

All strategies live under `Foqos/Models/Strategies/` and are orchestrated via `Foqos/Utils/StrategyManager.swift`.

- **NFC Tags (`NFCBlockingStrategy`)**

  - Start: scan any NFC tag to start the selected profile
  - Stop: scan the same tag to stop the session
  - **Physical Unblock (optional)**: set `physicalUnblockNFCTagId` on a profile to require that exact tag to stop (ignores the session’s start tag)

- **QR Codes (`QRCodeBlockingStrategy`)**

  - Start: scan any QR code to start the selected profile
  - Stop: scan the same QR code to stop the session
  - **Physical Unblock (optional)**: set `physicalUnblockQRCodeId` on a profile to require that exact code to stop (ignores the session’s start code)
  - The app can display/share a QR representing the profile’s deep link using `QRCodeView`

- **Manual (`ManualBlockingStrategy`)**

  - Start/Stop entirely from within the app (no external tag/code required)

- **NFC + Manual (`NFCManualBlockingStrategy`)**

  - Start: manually from within the app
  - Stop: scan any NFC tag (restricted to `physicalUnblockNFCTagId` if set)

- **QR + Manual (`QRManualBlockingStrategy`)**
  - Start: manually from within the app
  - Stop: scan any QR code (restricted to `physicalUnblockQRCodeId` if set)

### QR deep links

- Each profile exposes a deep link via `BlockedProfiles.getProfileDeepLink(profile)` in the form:
  - `https://foqos.app/profile/<PROFILE_UUID>`
- Scanning a QR that encodes this deep link will toggle the profile: if inactive it starts, if active it stops. This works even if the app isn’t already open (it will be launched via the link).

## 🤝 Contributing

We welcome contributions! Here's how you can help:

1. **Fork the repository**
2. **Make your changes** and test as much as you can
3. **Commit your changes** (`git commit -m 'Add amazing feature'`)
4. **Open a Pull Request**

### Contribution Guidelines

- Follow Swift coding conventions
- Update documentation as needed
- Test on multiple iOS versions when possible

## 🐛 Issues & Support

Having trouble? We're here to help!

- **Bug Reports**: [Open an issue](https://github.com/awaseem/foqos/issues) with detailed steps to reproduce
- **Feature Requests**: Share your ideas via [GitHub Issues](https://github.com/awaseem/foqos/issues)
- **Questions**: Use GitHub Discussions for general questions

When reporting issues, please include:

- iOS version
- Device model
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- [App Store](https://apps.apple.com/ca/app/foqos/id6736793117)
- [GitHub Issues](https://github.com/awaseem/foqos/issues)
- [Support the Project](https://apps.apple.com/ca/app/foqos/id6736793117) (via in-app purchases or [here](https://coff.ee/ambitionsoftware))

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/awaseem">Ali Waseem</a>
</p>
