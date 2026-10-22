# CleverTap Roku SDK

Analytics SDK for Roku channels, written in BrightScript / SceneGraph. It records events and
identifies users, and sends that data to CleverTap.

## Introduction

CleverTap brings together real-time user insights, an advanced segmentation engine, and
easy-to-use marketing tools in one platform, giving your team the power to create experiences
that deepen customer relationships.

For more information, check out our [website](https://clevertap.com/) and
[documentation](https://developer.clevertap.com/docs/). To get started, sign up
[here](https://clevertap.com/live-product-demo/).

## What this SDK covers

This first version is analytics only. It exposes four calls:

- `recordEvent` - record a custom event, with optional properties.
- `recordChargedEvent` - record a purchase with line items.
- `onUserLogin` - identify a user.
- `profilePush` - set attributes on the current user.

Eight more calls change one profile property without replacing it. See
[Profile commands](#profile-commands).

It also exposes `getCleverTapID`, which returns the current device id (the CleverTap ID) so
you can match a session to its profile in the dashboard.

## Requirements

- A Roku SceneGraph channel written in BrightScript.
- A CleverTap account. Your Account ID, Token, and region are in your CleverTap
  [Dashboard](https://dashboard.clevertap.com), under Settings -> Integration.

## Installation

The SDK is a set of BrightScript source files and SceneGraph components. Add it to your
channel by copying this repo's `source/` and `components/` folders into your channel's own
`source/` and `components/` folders. That registers the `CleverTap` node and its background
upload task.

## Integration

Create the SDK node once, keep it somewhere every component can reach, for example on
`m.global`, and initialize it.

```brightscript
' In your main scene's init():
ct = CreateObject("roSGNode", "CleverTap")
m.global.addFields({ clevertap: ct })

' Pass your credentials directly...
ct.callfunc("init", { accountId: "YOUR_ACCOUNT_ID", token: "YOUR_TOKEN", region: "in1" })
```

Or, instead of passing credentials in code, add them to your channel `manifest`:

```
clevertap_account_id=YOUR_ACCOUNT_ID
clevertap_token=YOUR_TOKEN
clevertap_region=in1
```

and call `init` with an empty object:

```brightscript
ct.callfunc("init", {})
```

## Usage

Once initialized, call the SDK from anywhere on the render thread through the node you stored:

```brightscript
ct = m.global.clevertap

' Identify a user
ct.callfunc("onUserLogin", [{ "Identity": "u123", "Email": "sam@example.com", "Name": "Sam" }])

' Set attributes on the current user
ct.callfunc("profilePush", [{ "Name": "Sam", "plan": "pro", "favTeam": "IND" }])

' Record an event, with optional properties
ct.callfunc("recordEvent", ["Product viewed", { "id": 42, "name": "Bat" }])

' Record a purchase with line items
ct.callfunc("recordChargedEvent", [{ "Amount": 300 }, [{ "id": 1 }, { "id": 2 }]])

' Get the current CleverTap device id (the CleverTap ID)
ctId = ct.callfunc("getCleverTapID", invalid)
```

### Always write property keys in quotes

Every key above is in quotes. This matters on Roku.

A key written without quotes inside `{ }` is an identifier to BrightScript, and BrightScript
identifiers are case-insensitive, so the device stores the key in lower case. `{ Amount: 300 }`
becomes `{ amount: 300 }` before the SDK ever sees it, and the original spelling is gone.

CleverTap matches reserved names exactly. `Amount` is the purchase value. `amount` is an
ordinary custom property, and the purchase is not reported as revenue. The same applies to
`Identity`, `Name`, `Email`, `Phone` and the other profile fields.

Nothing fails, so this is easy to miss. The SDK reports a key that looks like a reserved name
spelled in the wrong case:

```
[CleverTap] ERROR charge detail 'amount' is sent as a custom property. The server reads it as
'Amount' only when it is spelled that way. Write the key in quotes: { "Amount": ... }
```

Quoting every key is the simple rule that avoids the whole problem.

### Profile commands

`profilePush` replaces the value of a key. The calls below change one part of a value
instead, so you do not have to read the old value first.

```brightscript
ct = m.global.clevertap

' Remove a property from the profile
ct.callfunc("profileRemoveValueForKey", ["plan"])

' Replace the whole list of a multi-value property
ct.callfunc("profileSetMultiValues", ["favTeams", ["IND", "AUS"]])

' Put values into that list
ct.callfunc("profileAddMultiValue", ["favTeams", "ENG"])
ct.callfunc("profileAddMultiValues", ["favTeams", ["NZ", "SA"]])

' Take values out of that list
ct.callfunc("profileRemoveMultiValue", ["favTeams", "AUS"])
ct.callfunc("profileRemoveMultiValues", ["favTeams", ["NZ", "SA"]])

' Move a number property up or down
ct.callfunc("profileIncrementValueBy", ["points", 50])
ct.callfunc("profileDecrementValueBy", ["points", 20])
```

Every one of these takes its arguments in the same order: the property name first, then the
value.

A few rules worth knowing:

- A multi-value property holds text. A number you pass is turned into text, so `5` is stored
  as `"5"`. One property holds at most 100 values, and anything past that is dropped.
- The amount for an increment or a decrement must be above zero. To lower a value, use
  `profileDecrementValueBy` rather than a negative amount.
- The SDK keeps no copy of the profile, so it never merges a command with the current value.
  It sends the command and CleverTap applies it. This also means there is no way to read a
  property back on the device.
- A call with a bad property name or a bad value is dropped and logged. Nothing else in the
  queue is affected.

## Sample channel

A runnable sample lives in [`sample/`](sample/). It starts the SDK and shows a menu of these
calls; select a row and press OK to fire that call, then check your CleverTap dashboard. See
[`sample/README.md`](sample/README.md) for how to assemble and sideload it.

## Development

Building the SDK from source and running its tests is covered in
[DEVELOPMENT.md](DEVELOPMENT.md).

## License

MIT, as declared in `package.json`.
