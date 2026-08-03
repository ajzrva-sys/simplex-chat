# Native Chat for macOS

Native Chat is an independent native SwiftUI/AppKit macOS frontend compatible with the SimpleX network. It links to the existing desktop core and opens the existing desktop database at `~/.local/share/simplex`.

It does not use Compose, change the core protocol, or introduce a second message format.

Native Chat is a modified work based on SimpleX Chat. Material modifications
began on August 2, 2026; see [MODIFICATIONS.md](MODIFICATIONS.md). The application
is released under the repository's GNU AGPL v3 license. Native Chat is not
affiliated with or endorsed by SimpleX Chat Ltd.

Build the app after the desktop core libraries have been staged:

```sh
./build-app.sh
```

The resulting application is `/private/tmp/native-chat-build/Native Chat.app`. Set
`NATIVE_CHAT_OUTPUT_DIR` to stage it elsewhere. Only one compatible frontend may
open the desktop database at a time.

Development builds are self-signed and identify their source as the active
`macos-native` branch when the working tree has uncommitted changes. Clean builds
link to their exact commit. Set `NATIVE_CHAT_VERSION` and
`NATIVE_CHAT_BUILD_NUMBER` when preparing a release.

The app bundle includes the GNU AGPL v3 text, modification and warranty notices,
the source location, and the upstream third-party dependency licenses. These are
also available from **Native Chat → About Native Chat**.
