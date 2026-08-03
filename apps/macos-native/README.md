# Native Chat for macOS

Native Chat is an independent native SwiftUI/AppKit macOS frontend compatible with the SimpleX network. It links to the existing desktop core and opens the existing desktop database at `~/.local/share/simplex`.

It does not use Compose, change the core protocol, or introduce a second message format.

Build the app after the desktop core libraries have been staged:

```sh
./build-app.sh
```

The resulting application is `/private/tmp/native-chat-build/Native Chat.app`. Set
`NATIVE_CHAT_OUTPUT_DIR` to stage it elsewhere. Only one compatible frontend may
open the desktop database at a time.
