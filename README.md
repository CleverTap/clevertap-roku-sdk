# CleverTap Roku SDK

Analytics for Roku channels, written in BrightScript / SceneGraph. It records events and
identifies users, and sends that data to CleverTap.

CleverTap brings together real-time user insights, an advanced segmentation engine, and
easy-to-use marketing tools in one platform. See our [website](https://clevertap.com/) and
[documentation](https://developer.clevertap.com/docs/), or sign up
[here](https://clevertap.com/live-product-demo/).

## Quick start

You need a Roku SceneGraph channel, and an Account ID, Token and region from your CleverTap
[Dashboard](https://dashboard.clevertap.com) under Settings -> Integration.

**1. Install.** Run both commands from your channel root, the folder that holds `manifest`.

```bash
npm install ropm --save-dev
npx ropm install clevertap-roku-sdk
```

This is the ropm route. There is a second route for channels that cannot add a build step,
and it changes the node name used in step 3. See [Installation](#installation).

**2. Add your credentials** to the channel `manifest`.

```
clevertap_account_id=YOUR_ACCOUNT_ID
clevertap_token=YOUR_TOKEN
clevertap_region=YOUR_REGION
clevertap_log_level=debug
```

**3. Start the SDK** once, in your main scene's `init()`.

```brightscript
ct = CreateObject("roSGNode", "clevertaprokusdk_CleverTap")
m.global.addFields({ clevertap: ct })
ct.callfunc("init", {})
```

**4. Record something** from anywhere on the render thread.

```brightscript
ct = m.global.clevertap
ct.callfunc("onUserLogin", [{ "Identity": "u123", "Email": "sam@example.com" }])
ct.callfunc("recordEvent", ["Product viewed", { "id": 42, "name": "Bat" }])
```

That is a working integration. The rest of this page is detail.

> **Three rules that cause silent data loss.** Read these before you write much code.
> 1. Always write property keys **in quotes**. See [Quote every key](#quote-every-key).
> 2. Every call except `init` takes a **list** of arguments. See [Argument shapes](#argument-shapes).
> 3. `npm install clevertap-roku-sdk` does **not** work. Use `ropm`. See [Installation](#installation).

## What you can call

Version 1 is analytics only. Every call is made on the SDK node through `callfunc`.

| Call | What it does |
| --- | --- |
| `init` | Start the SDK. Call once before anything else. |
| `recordEvent` | Record a custom event, with optional properties. |
| `recordChargedEvent` | Record a purchase with line items. |
| `onUserLogin` | Identify a user. |
| `profilePush` | Set attributes on the current user. |
| `getCleverTapID` | Return this device's CleverTap ID, to match a session to a dashboard profile. |

Eight more calls change one profile property without replacing it. See
[Profile commands](#profile-commands).

| Call | What it does |
| --- | --- |
| `profileRemoveValueForKey` | Remove a property. |
| `profileSetMultiValues` | Replace a whole list property. |
| `profileAddMultiValue` / `profileAddMultiValues` | Add to a list property. |
| `profileRemoveMultiValue` / `profileRemoveMultiValues` | Remove from a list property. |
| `profileIncrementValueBy` / `profileDecrementValueBy` | Move a number property. |

Two cover privacy. See [Privacy and GDPR](#privacy-and-gdpr).

| Call | What it does |
| --- | --- |
| `setOptOut` | Stop or resume reporting for this viewer. |
| `enableDeviceNetworkInfoReporting` | Turn network detail reporting on or off. |

## Installation

The SDK is a set of BrightScript source files and SceneGraph components. There are **two
routes, and you pick one**. They give the SDK node a different name, so the choice changes
the code you write.

| | **ropm** (recommended) | **Manual integration** |
| --- | --- | --- |
| How | `npx ropm install clevertap-roku-sdk` | copy two folders into your channel |
| Needs a build step | yes | no |
| Node name you create | `clevertaprokusdk_CleverTap` | `CleverTap` |
| Used by the sample | yes | no |

> **`npm install clevertap-roku-sdk` is not a third route.** It exits 0, installs nothing your
> channel can use, and fails only at runtime. See
> [below](#why-npm-install-clevertap-roku-sdk-does-not-work).

Every code sample on this page uses the ropm name, `clevertaprokusdk_CleverTap`. On the
manual route, write `CleverTap` instead, everywhere.

### Route 1: ropm (recommended)

Run both commands from your channel root, the folder that holds `manifest`. ropm works from
the current directory, so running it a level up writes the SDK where your channel cannot see
it.

```bash
npm install ropm --save-dev
npx ropm install clevertap-roku-sdk
```

ropm copies the SDK into `source/roku_modules/clevertaprokusdk/` and
`components/roku_modules/clevertaprokusdk/`. Commit those folders, or re-run
`npx ropm install` in your build.

**The node is named with a prefix.** ropm prefixes every package so two packages cannot
register the same component name, so the node is **`clevertaprokusdk_CleverTap`**, not
`CleverTap`. The prefix applies to the node name only. Call names stay plain, so
`callfunc("init", ...)` is written exactly as it appears here.

<details>
<summary><b>Checking the ropm install really happened</b></summary>

```bash
ls source/roku_modules/clevertaprokusdk
```

Worth doing, because `ropm install` exits 0 even when it installed nothing. A build step that
only reads the exit code will carry on and produce a channel with no SDK in it. The first sign
of trouble is the node failing to create at runtime. ropm's own last line is the other tell:
`ropm: Installed 1 module` rather than `ropm: No modules installed`.
</details>

### Route 2: manual integration

Use this only if you cannot add a build step. Copy this repo's `source/` and `components/`
folders into your channel's own `source/` and `components/`.

Nothing renames anything on this route, so the node is plain **`CleverTap`**. That is the one
difference. Change the node name in every example on this page, and leave everything else as
written.

```brightscript
ct = CreateObject("roSGNode", "CleverTap")   ' manual integration
```

### Why `npm install clevertap-roku-sdk` does not work

npm appears in Route 1, but only to install ropm, which is a tool. The SDK itself is installed
by the `ropm` command.

`npm install clevertap-roku-sdk` looks like it worked. It prints no error and exits with a
success code. It downloads the real files into `node_modules/clevertap-roku-sdk/`.

A channel zip holds `manifest`, `source/`, `components/` and `images/`. The `node_modules`
folder is not one of them, so the SDK never reaches the device. The channel still builds. The
problem appears only at runtime, when the channel cannot create the SDK node.

## Integration

Create the SDK node once, keep it where every component can reach it, and initialize it.

```brightscript
' In your main scene's init():
ct = CreateObject("roSGNode", "clevertaprokusdk_CleverTap")
m.global.addFields({ clevertap: ct })

' Credentials in code...
ct.callfunc("init", { accountId: "YOUR_ACCOUNT_ID", token: "YOUR_TOKEN", region: "in1" })

' ...or in the manifest, and then:
ct.callfunc("init", {})
```

<details>
<summary><b>Putting the channel on a device</b></summary>

Nothing here is specific to the SDK, but you need it to see any of the above work.

A Roku channel is a zip with `manifest` at the top level. Build it from **inside** your
channel root, or the manifest ends up in a subfolder and the device rejects the zip:

```bash
zip -r ../my-channel.zip manifest source components
```

Put the device in developer mode, then open `http://<roku-ip>` in a browser and upload the
zip. The remote sequence for developer mode, and how to find the device IP, are in
[`sample/RUN_ON_DEVICE.md`](sample/RUN_ON_DEVICE.md), steps 1 and 2.

To watch the SDK, connect to the debug console before you sideload:

```bash
nc <roku-ip> 8085
```

With `clevertap_log_level=debug` you should see:

```
[CleverTap] initialized, account TEST-123-4567, sdk 1.0.0
[CleverTap] event recorded: App Launched
[CleverTap] response status 200, body {"status":"success",...}
```

No `[CleverTap]` lines at all usually means the account id or token is missing. The SDK
reports that once and then stays inactive.
</details>

## Usage

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

' Get this device's CleverTap ID
ctId = ct.callfunc("getCleverTapID", invalid)
```

### Quote every key

Every key above is in quotes. This matters on Roku.

A key written without quotes inside `{ }` is an identifier to BrightScript, and BrightScript
identifiers are case-insensitive. The device stores the key in lower case. `{ Amount: 300 }`
becomes `{ amount: 300 }` before the SDK sees it, and the original spelling is gone.

CleverTap matches reserved names exactly. `Amount` is the purchase value. `amount` is an
ordinary custom property, and **the purchase is not reported as revenue**. The same applies to
`Identity`, `Name`, `Email`, `Phone` and the other profile fields.

Nothing fails, so this is easy to miss. The SDK reports a reserved name in the wrong case:

```
[CleverTap] ERROR charge detail 'amount' is sent as a custom property. The server reads it as
'Amount' only when it is spelled that way. Write the key in quotes: { "Amount": ... }
```

### Argument shapes

`init` is handed your config map directly. Every other call is handed a **list holding its
arguments in order**.

```brightscript
ct.callfunc("init", { accountId: "...", token: "..." })        ' a map
ct.callfunc("recordEvent", ["Product viewed", { "id": 42 }])   ' a list
```

A call taking one argument still takes a list of one. A call taking nothing is passed
`invalid`.

```brightscript
ct.callfunc("profilePush", [{ "Name": "Sam" }])    ' right
ct.callfunc("profilePush", { "Name": "Sam" })      ' wrong
ct.callfunc("getCleverTapID", invalid)             ' takes nothing
```

Nothing stops you at build time, because `callfunc` names and arguments are not checked until
the line runs. Passing a map where a list belongs fails there, with
`Associative array indexes must be strings`. The call never happens, so the event or profile
change is never recorded.

### Dates

`DOB`, `Birthday`, any custom attribute and any event property can hold a date. Write it as a
map with one key, `date`. The value is either an ISO 8601 date and time, or a count of seconds
from 1 January 1970.

```brightscript
ct.callfunc("profilePush", [{ "DOB": { "date": "1990-04-17T00:00:00Z" } }])
ct.callfunc("profilePush", [{ "DOB": { "date": 640310400 } }])
ct.callfunc("recordEvent", ["Watched", { "airedOn": { "date": 640310400 } }])
```

Both profile lines send the same thing. On the wire the value becomes `"$D_640310400"`. A date
before 1970 is a negative count and works the same way: 3 March 1965 is `"$D_-152496000"`.

A plain number is **not** read as a date. The SDK cannot tell a second count apart from a score
or a price, so `{ "DOB": 640310400 }` stores the number. Use the map whenever you mean a date.

A date the device cannot read is reported and left out. It is not sent as 1 January 1970, and
it does not replace a date CleverTap already holds.

```
[CleverTap] ERROR date for 'DOB' could not be read from '17 April 1990', so it was left out.
Write the date as "1990-04-17T00:00:00Z", with a T between the date and the time.
```

<details>
<summary><b>Dates nested inside events and purchases</b></summary>

The SDK looks inside maps and lists, so a date is found wherever you write it. The line items
of a purchase are a list of maps, and a date in one of them works the same way:

```brightscript
ct.callfunc("recordChargedEvent", [
    { "Amount": 300, "boughtOn": { "date": 640310400 } },
    [{ "id": 1, "name": "Match ticket", "airedOn": { "date": 640310400 } }]
])
```

The search goes three levels down, counting maps and lists. A value deeper than that is sent
without the parts inside it, and a date written down there stays a map:

```
[CleverTap] ERROR 'a.b.c.d' is nested more than 3 levels deep. Its own values were sent, and
anything nested inside it was left out. A date written this deep is not converted.
```

Any map carrying a `date` key is read as a date before the SDK looks at it as nested data.
Whatever else that map holds is dropped, so give the date a map of its own.
</details>

<details>
<summary><b>Why a map and not <code>roDateTime</code></b></summary>

BrightScript has a date object, `roDateTime`, but you cannot hand one to the SDK. Every call
reaches the SDK through `callfunc`, and an `roDateTime` does not survive that call. It arrives
as nothing. A map does survive, which is why the date is written as one.

The three-level limit also keeps a mistake cheap. A map can be made to hold itself:

```brightscript
show = {}
show["self"] = show    ' don't do this
```

Roku's JSON writer refuses a value like that. Without the limit, one such property would make
every event waiting on the device unsendable. The SDK copies what you give it, so a value that
holds itself costs you that one property and nothing else.
</details>

### Nested properties

A property can hold a map or a list, not just a single value.

```brightscript
ct.callfunc("recordEvent", ["Product viewed", {
    "id": 42
    "show": {
        "title": "Final over"
        "airedOn": { "date": 640310400 }
        "teams": ["IND", "AUS"]
    }
}])
```

> **Nesting has to be switched on for your account.** The SDK sends a nested value as written,
> but CleverTap only stores it once the feature is enabled. Event properties and profile
> attributes are switched on separately, so ask the CleverTap team for both if you need both.
> Until then the request still succeeds, the console still shows the nested payload going out,
> and the value is dropped on arrival. Nothing is logged at either end.

Once on, CleverTap flattens what you send. Each value inside becomes its own property, named by
the path it sat at. The `show` map above arrives as three properties, next to the flat `id`:

```
show.title     Final over
show.airedOn   17/04/1990
show.teams     IND, AUS
```

A list adds its position to the name, so a map inside a list is `teams[0].city`. Build your
dashboard reports against those names.

Two exceptions. CleverTap does not flatten anything inside a `Charged` event, so keep line
items flat and put nested data on an event of your own. A date is unaffected, because it stops
being a map before it leaves the device. The nesting limit is the same three levels the date
search uses.

### Phone numbers

Write a phone number in quotes, with a leading `+` and its country code.

```brightscript
ct.callfunc("profilePush", [{ "Phone": "+14155550123" }])
```

Write it as text. `{ "Phone": 14155550123 }` is a number, and a number cannot hold a leading
`+` or a leading zero.

A number without a `+` still works when the device reports a country, because CleverTap
completes it from there. Some Roku devices report no country, and then it cannot be completed.
The SDK reports that and sends the number anyway. The SDK never changes or drops a phone
number, because only your app knows what it meant.

```
[CleverTap] ERROR Phone '4155550123' carries no country code, and this device reports no
country either. The server may not be able to use the number.
```

### Profile commands

`profilePush` replaces the value of a key. These change one part of a value instead, so you do
not have to read the old value first. Each takes the property name first, then the value.

```brightscript
ct = m.global.clevertap

' Remove a property
ct.callfunc("profileRemoveValueForKey", ["plan"])

' Replace a whole list property
ct.callfunc("profileSetMultiValues", ["favTeams", ["IND", "AUS"]])

' Add to that list
ct.callfunc("profileAddMultiValue", ["favTeams", "ENG"])
ct.callfunc("profileAddMultiValues", ["favTeams", ["NZ", "SA"]])

' Remove from that list
ct.callfunc("profileRemoveMultiValue", ["favTeams", "AUS"])
ct.callfunc("profileRemoveMultiValues", ["favTeams", ["NZ", "SA"]])

' Move a number property
ct.callfunc("profileIncrementValueBy", ["points", 50])
ct.callfunc("profileDecrementValueBy", ["points", 20])
```

- A list property holds text. A number is converted, so `5` is stored as `"5"`. One property
  holds at most 100 values, and anything past that is dropped.
- An increment or decrement amount must be above zero. To lower a value use
  `profileDecrementValueBy`, not a negative amount.
- The SDK keeps no copy of the profile. It sends the command and CleverTap applies it. No
  property can be read back on the device.
- A call with a bad property name or value is dropped and logged. Nothing else in the queue is
  affected.

## Privacy and GDPR

### Right to suppress - opt out

A viewer can ask not to be reported. Your app offers that choice, then tells the SDK.

```brightscript
ct.callfunc("setOptOut", [true])         ' stop reporting this viewer
ct.callfunc("setOptOut", [false])        ' report this viewer again
ct.callfunc("setOptOut", [true, true])   ' drop your data, keep session bookkeeping
```

While a viewer is opted out, nothing is sent. Events are dropped before they are queued, so
they do not sit on the device either.

| | you record an event | `recordChargedEvent` | `App Launched` | profile changes |
| --- | --- | --- | --- | --- |
| opted in (default) | sent | sent | sent | sent |
| `[true, true]` | dropped | dropped | sent | sent |
| `[true]` | dropped | dropped | dropped | dropped |

The second argument keeps the SDK's own bookkeeping flowing. The only such event is
`App Launched`, which tells CleverTap a session started. Without it, sessions on the server
never close. Use it when a viewer asked not to be tracked but you still need usage figures that
name nobody. A purchase is **not** bookkeeping, so `recordChargedEvent` is dropped either way.

The SDK sends the choice to CleverTap as a profile attribute, so server-built campaigns are
suppressed too. It then keeps the choice on the device against that viewer's CleverTap ID, so
the viewer does not opt out again next launch, and signing out and back in does not reset it.

The default is to report. Your app is still where the answer really lives, so calling
`setOptOut` with the stored answer on every launch is good practice.

### Device network information

The SDK reports nothing about the network, and tells CleverTap not to work out where a viewer
is from the request address. To turn that on:

```brightscript
ct.callfunc("enableDeviceNetworkInfoReporting", [true])
```

That adds whether the device is on WiFi rather than a cable, and lets CleverTap read an
approximate location from the request address. A Roku device has no mobile radio, so unlike the
mobile SDKs there is no carrier to report. This is off unless you turn it on, and the setting
is kept on the device.

### Marketing opt out

To take a viewer out of all marketing channels, set these attributes. This needs no special
call. By default every channel is available.

```brightscript
ct.callfunc("profilePush", [{
    "MSG-email": false
    "MSG-push": false
    "MSG-sms": false
    "MSG-push-all": false
}])
```

## Sample channel

A runnable sample lives in [`sample/`](sample/). It starts the SDK and shows a menu of these
calls. Select a row and press OK to fire it, then check your dashboard. See
[`sample/README.md`](sample/README.md) for how to assemble and sideload it.

## Development

Building the SDK from source and running its tests is covered in
[DEVELOPMENT.md](DEVELOPMENT.md).

## License

MIT, as declared in `package.json`.
