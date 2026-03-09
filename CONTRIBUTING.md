# Contributing to OpenWhisper

Thanks for your interest in contributing! All contributions are welcome — bug reports, feature requests, and pull requests.

## Getting started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/OpenWhisper.git
   ```
3. Open the project in Xcode:
   ```bash
   cd OpenWhisper/OpenWhisper
   open OpenWhisper.xcodeproj
   ```
4. Update the development team in **Signing & Capabilities** to your own Apple ID
5. Build and run (Cmd + R)

## Pull requests

- All PRs require review and approval before merging
- Keep PRs focused — one feature or fix per PR
- Write a clear description of what changed and why
- Make sure the project builds without warnings
- Test your changes on macOS before submitting

### Branch naming

- `feature/short-description` for new features
- `fix/short-description` for bug fixes
- `docs/short-description` for documentation changes

## Bug reports

When reporting bugs, include:

- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Console logs if applicable (open Console.app and filter by "OpenWhisper")

## Code style

- Follow existing code conventions in the project
- Use Swift's standard naming conventions (camelCase for variables/functions, PascalCase for types)
- Keep files focused — one main type per file

## Architecture overview

```
OpenWhisper/
├── Models/          # State management and data models
├── Services/        # Business logic (audio, transcription, hotkeys, etc.)
├── Views/           # SwiftUI views
└── Utilities/       # Constants and helpers
```

Key patterns:
- **AppState** is the central observable state object
- Services are initialized and owned by AppState
- Views observe AppState for reactivity

## Questions?

Open an issue with the **question** label and we'll help you out.
