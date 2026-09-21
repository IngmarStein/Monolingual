# Finishing the Swift XPC migration

Everything below was verified by type-checking against the macOS 27 SDK, not by guessing. The
branch switches the helper's transport from `NSXPCConnection` + `@objc` protocols (which required
`NSSecureCoding` payloads and a pid-based peer check) to the Swift XPC API.

## What is already done here

- `HelperRequest` is a `Codable`, `Sendable` struct — its `NSSecureCoding` plumbing is gone.
- Both `@objc` protocols are replaced by `HelperMessage` / `HelperReply` and the constants in
  `HelperService`.
- The peer check is now declarative: the listener is created with
  `XPCPeerRequirement.isFromSameTeam(andMatchesSigningIdentifier:)`, which XPC enforces for every
  session before any code runs. This replaces the pid-based `SecCodeCheckValidity` check and is
  strictly stronger — no pid-reuse window.

## The API shapes, verified

**Sending.** `XPCSession.send` takes a dictionary whose values must all have the same type:

```swift
try session.send(["progress": endpoint])   // [String: XPCEndpoint]
try session.send(["payload": data])        // [String: Data]
```

That is why the endpoint and the payload travel as **two messages**: `["payload": data,
"progress": endpoint]` does not compile. The helper remembers the endpoint it was last sent.

**Receiving.** The listener accepts an `XPCDictionary`. There is no Swift accessor for its
contents — `XPCDictionary`'s subscript is not for `Data` — so payload bytes come out through the
escape hatch and the C call:

```swift
let data = try dictionary.withUnsafeUnderlyingDictionary { underlying in
    var length = 0
    guard let bytes = xpc_dictionary_get_data(underlying, "payload", &length) else { throw … }
    return Data(bytes: bytes, count: length)
}
let endpoint = dictionary["progress"].map { XPCEndpoint($0) }   // xpc_object_t → XPCEndpoint
```

**Messages.** `HelperMessage`/`HelperReply` stay `Codable`; `XPCReceivedMessage.decode(as:)` and
`.reply(_:)` are available on the session-accept form, `expectsReply`/`isSync` tell you whether a
reply is wanted. A client applies its own requirement with `XPCSession.setPeerRequirement(_:)`.

## What is left

1. `Helper.swift`: create the `XPCListener` in `run()` with the requirement, handle messages on a
   worker queue, report `progress` and `finished` over the endpoint session.
2. `HelperContext.swift`: report progress as `HelperReply.progress` messages instead of the
   cross-process `Progress`/`ProgressProtocol` workaround. This is what deletes the last of the
   `NSXPCConnection` machinery.
3. `HelperTask.swift`: drive an `XPCSession` plus an anonymous `XPCListener` for progress and the
   exit code.
4. Delete `HelperInstaller.removeLegacyInstallation()` and the `…Helper` Mach-lookup exception from
   `Monolingual.entitlements` — no longer needed, since the new daemon has its own Mach service.
5. `let` → `var` for `HelperRequest` in the tests and in `main.swift`.
6. Build, tests, then the daemon verification: spawn, version, a real removal, and the
   foreign-client rejection, which now exercises the declarative requirement.
