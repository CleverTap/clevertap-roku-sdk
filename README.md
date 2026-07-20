# CleverTap Roku SDK

Analytics SDK for Roku channels written in BrightScript / SceneGraph. It records events
and identifies users, sending them to CleverTap. This first version covers analytics only:

- `recordEvent` (with optional properties)
- `recordChargedEvent`
- `onUserLogin` (identify a user)
- `profilePush` (set profile attributes)

## Install

```
ropm install clevertap
```

This pulls the SDK into your channel's `source/` and `components/` under the `clevertap`
namespace.

## Quick start

```brightscript
' In your main scene's init():
ct = CreateObject("roSGNode", "clevertap:CleverTap")
m.global.addFields({ clevertap: ct })

' Pass credentials directly...
ct.callfunc("init", { accountId: "YOUR_ACCOUNT_ID", token: "YOUR_TOKEN", region: "in1" })

' ...or leave them out and add clevertap_account_id / clevertap_token / clevertap_region
' to your channel manifest, then:
ct.callfunc("init", {})
```

Record events and profiles from anywhere on the render thread:

```brightscript
ct.callfunc("recordEvent", ["Product viewed", { id: 42, name: "Bat" }])
ct.callfunc("recordChargedEvent", [{ Amount: 300 }, [{ id: 1 }, { id: 2 }]])
ct.callfunc("onUserLogin", [{ Identity: "u123", Email: "sam@x.com", Name: "Sam" }])
ct.callfunc("profilePush", [{ Name: "Sam", plan: "pro", favTeam: "IND" }])
```

## Sample channel

A runnable sample lives in [`sample/`](sample/). It starts the SDK and fires one of each
call on launch so you can verify things end to end against a test account. See
[`sample/README.md`](sample/README.md) for how to assemble and sideload it.

## Development

Requires Node.js. Install tooling with `npm install`, then:

- `npm run build` type-checks the source and components with the BrighterScript compiler.
- `npm test` runs the unit suite headlessly with the [brs](https://github.com/sjbarag/brs)
  interpreter - no Roku device needed. The pure logic (device, session, queue, validation,
  request building, networking decisions, profile, login) is covered here; the SceneGraph
  node wiring is verified by sideloading the sample against a test account.

Both run in CI on every push and pull request.
