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

Two calls cover privacy. See [Privacy and GDPR](#privacy-and-gdpr).

- `setOptOut` - stop or resume reporting for the current viewer.
- `enableDeviceNetworkInfoReporting` - turn reporting of network details on or off.

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

### Dates

`DOB`, `Birthday` and any custom attribute can hold a date. Write the date as a map with one
key, `date`. The value is either an ISO 8601 date and time, or a count of seconds from
1 January 1970:

```brightscript
ct.callfunc("profilePush", [{ "DOB": { "date": "1990-04-17T00:00:00Z" } }])
ct.callfunc("profilePush", [{ "DOB": { "date": 640310400 } }])
```

Both lines send the same thing. On the wire the value becomes `"$D_640310400"`: the number of
seconds from 1 January 1970, behind a prefix that marks the value as a date.

A date before 1 January 1970 is a negative second count, and that works the same way. 3 March
1965 is sent as `"$D_-152496000"`.

Write the ISO 8601 date with a `T` between the date and the time, as above. Roku also
documents a form with a space in place of the `T`, but the device does not read it.

An event property can be a date too:

```brightscript
ct.callfunc("recordEvent", ["Watched", { "airedOn": { "date": 640310400 } }])
```

The SDK looks inside maps and lists, so a date is found wherever you write it. The line
items of a purchase are a list of maps, and a date in one of them works the same way:

```brightscript
ct.callfunc("recordChargedEvent", [
    { "Amount": 300, "boughtOn": { "date": 640310400 } },
    [{ "id": 1, "name": "Match ticket", "airedOn": { "date": 640310400 } }]
])
```

The search goes three levels down, counting both maps and lists. A value nested deeper than
that is sent without the parts nested inside it, and a date written down there stays a map
rather than becoming a date. The SDK says so:

```
[CleverTap] ERROR 'a.b.c.d' is nested more than 3 levels deep. Its own values were sent, and
anything nested inside it was left out. A date written this deep is not converted.
```

**Nesting has to be switched on for your account.** The SDK sends a nested value as written,
but CleverTap only stores it once the feature is enabled. Event properties and profile
attributes are switched on separately, so ask the CleverTap team for both if you need both.
Until then the request still succeeds, the console still shows the nested payload going out,
and the value is dropped on arrival. Nothing is logged at either end, so the only sign is
that the data never reaches the dashboard.

Once it is on, CleverTap flattens what you send. It does not keep the nesting. Each value
inside becomes its own property, named by the path it sat at, and the map itself is not a
property you can report on. The event above arrives as three properties:

```
show.title     Final over
show.airedOn   17/04/1990
show.teams     IND, AUS
```

A list adds its position to the name, so `teams[0].city` is what a map inside a list is
called. Build your dashboard reports against those names.

Two things this does not cover. A purchase is left out: CleverTap does not flatten anything
inside a `Charged` event, so keep the line items of a purchase flat and put nested data on
an event of your own. A date is not affected either way, because it stops being a map before
it leaves the device - it travels as plain text and lands as a date wherever you wrote it.

The limit is also what keeps a mistake cheap. A map can be made to hold itself:

```brightscript
show = {}
show["self"] = show    ' don't do this
```

Roku's JSON writer refuses a value like that. Without the limit, one such property would
make every event waiting on the device unsendable. The SDK copies what you give it, so a
value that holds itself costs you that one property and nothing else.

**Why a map and not `roDateTime`.** BrightScript has a date object, `roDateTime`, but you
cannot hand one to the SDK. Every call reaches the SDK through `callfunc`, and an
`roDateTime` does not survive that call. It arrives as nothing. A map does survive, which is
why the date is written as one.

Any map that carries a `date` key is read as a date, before the SDK looks at it as nested
data. Whatever else that map holds is dropped, so give the date a map of its own.

A number on its own is **not** read as a date:

```brightscript
' Stored as the number 640310400, not as a date.
ct.callfunc("profilePush", [{ "DOB": 640310400 }])
```

The SDK cannot tell a second count apart from a score or a price, so it leaves a plain number
alone. Use the map whenever you mean a date.

A date the device cannot read is left out of the request and reported. It is not sent as
1 January 1970, and it does not replace a date CleverTap already holds:

```
[CleverTap] ERROR date for 'DOB' could not be read from '17 April 1990', so it was left out.
Write the date as "1990-04-17T00:00:00Z", with a T between the date and the time.
```

### Phone numbers

Write a phone number in quotes, with a leading `+` and its country code:

```brightscript
ct.callfunc("profilePush", [{ "Phone": "+14155550123" }])
```

A number without a `+` still works when the device reports a country, because CleverTap
completes it from there. Some Roku accounts report no country, and then a number without a
`+` cannot be completed. The SDK reports that case and sends the number anyway:

```
[CleverTap] ERROR Phone '4155550123' carries no country code, and this device reports no
country either. The server may not be able to use the number.
```

Write the number as text. `{ "Phone": 14155550123 }` is a number, and a number cannot hold a
leading `+` or a leading zero. The SDK reports that too.

The SDK never changes or drops a phone number. Only your app knows what it meant, so both
checks are reports.

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

## Privacy and GDPR

### Right to suppress - opt out

A viewer can ask not to be reported. Your app offers that choice in its own settings, then
tells the SDK:

```brightscript
' Stop reporting this viewer.
clevertap.callfunc("setOptOut", [true])

' Report this viewer again.
clevertap.callfunc("setOptOut", [false])
```

While a viewer is opted out, nothing is sent. Events you record are dropped before they are
queued, so they do not sit on the device waiting either.

There is a middle setting. Pass a second argument to keep the SDK's own bookkeeping events
flowing while everything you record is still dropped:

```brightscript
clevertap.callfunc("setOptOut", [true, true])
```

The only such event this SDK sends is `App Launched`, which tells CleverTap a session
started. Without it, sessions on the server never close. Use this when a viewer asked not to
be tracked but you still need usage figures that name nobody. A purchase is **not** treated
as a bookkeeping event, so `recordChargedEvent` is dropped under either setting.

| | you record an event | `recordChargedEvent` | `App Launched` | profile changes |
| --- | --- | --- | --- | --- |
| opted in (default) | sent | sent | sent | sent |
| `[true, true]` | dropped | dropped | sent | sent |
| `[true]` | dropped | dropped | dropped | dropped |

The SDK sends the choice to CleverTap as a profile attribute, so campaigns built on the
server are suppressed too. It then keeps the choice on the device, against that viewer's
CleverTap ID. The viewer does not have to opt out again next launch, and a viewer who signs
out and back in is still opted out.

By default the SDK reports, and the opt-out is false. Your app is still the place the answer
really lives, so calling `setOptOut` with the stored answer on every launch is good practice.

### Device network information

The SDK reports nothing about the network, and tells CleverTap not to work out where a
viewer is from the address the request came from. To turn that on:

```brightscript
clevertap.callfunc("enableDeviceNetworkInfoReporting", [true])
```

That adds whether the device is on WiFi rather than a cable, and lets CleverTap read an
approximate location from the request address. A Roku device has no mobile radio, so unlike
the mobile SDKs there is no carrier or mobile network to report.

This is off unless you turn it on, and the setting is kept on the device.

### Marketing opt out

To take a viewer out of all marketing channels, set these attributes on their profile. This
needs no special call:

```brightscript
clevertap.callfunc("profilePush", [{
    "MSG-email": false
    "MSG-push": false
    "MSG-sms": false
    "MSG-push-all": false
}])
```

By default every channel is available.

## Sample channel

A runnable sample lives in [`sample/`](sample/). It starts the SDK and shows a menu of these
calls; select a row and press OK to fire that call, then check your CleverTap dashboard. See
[`sample/README.md`](sample/README.md) for how to assemble and sideload it.

## Development

Building the SDK from source and running its tests is covered in
[DEVELOPMENT.md](DEVELOPMENT.md).

## License

MIT, as declared in `package.json`.
