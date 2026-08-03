# Native Chat modifications

Native Chat is a modified version of SimpleX Chat. Material changes began on
August 2, 2026.

The changes include:

- an independent native SwiftUI and AppKit interface for macOS;
- macOS-specific window, keyboard, notification, Keychain, media, and
  accessibility behavior;
- native chat, contact, profile, linked-device, call, transfer, and settings
  surfaces that use the existing SimpleX core; and
- separate arm64 application packaging and release automation for macOS 14 and
  later.

Native Chat does not intentionally change the SimpleX wire protocol, transport,
or database schema. The complete change history is available from the source
code link shown in the application’s About window.
