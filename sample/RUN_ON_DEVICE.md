# Run the sample on a real Roku device

Build the sample channel, load it onto a Roku device, and read the SDK's log output.

This is the setup that can check what the SDK really sends. The browser simulator cannot do
that. See [RUN_ON_SIMULATOR.md](RUN_ON_SIMULATOR.md) if you have no device.

## What you need

- A Roku device. A Streaming Stick plugged into any HDMI screen is enough.
- The device and your computer on the **same network**. Sideloading and the log console both
  talk to the device directly.
- [Node.js](https://nodejs.org) installed. Check it with `node -v`.

## 1. Put the device in developer mode

On the Roku remote, press:

**Home x3, Up x2, Right, Left, Right, Left, Right**

A Developer Settings screen appears. Enable developer mode, accept the agreement, and set a
password. Write the password down. You need it every time you sideload, and the only way to
see it again is to repeat this sequence.

The device restarts afterwards.

## 2. Find the device's IP address

On the device: **Settings -> Network -> About**. Note the IP address, for example
`192.168.1.42`.

Everything below uses `<roku-ip>` to mean that address.

## 3. Build the channel zip

From the **repo root**:

```
npm run sample:zip
```

One command. It runs the unit tests, compiles the SDK, packs it, reinstalls it into the
sample, checks the sample really got your current code, and writes the zip.

It prints the path at the end:

```
Sideload this: /path/to/clevertap-roku-sdk/clevertap-roku-sample.zip
```

If any step fails the zip is not written, so you cannot sideload a build that did not compile.

## 4. Start watching the logs

Do this **before** you sideload. The most interesting lines are printed during startup, and
you cannot get them back once they have scrolled past.

The SDK prints to the BrightScript debug console on port 8085. macOS removed `telnet`, so use
`nc`:

```
nc <roku-ip> 8085
```

On Windows, use PuTTY in Raw or Telnet mode against port 8085.

Leave this running in its own terminal window.

## 5. Sideload the zip

Open `http://<roku-ip>` in a browser. That is the Development Application Installer.

1. Sign in. The username is `rokudev` and the password is the one from step 1.
2. Choose the zip from step 3.
3. Click **Replace** (or **Install** the first time).

The channel launches on the device.

## 6. Read the output

In the `nc` window you should see something like this:

```
[CleverTap] initialized, account W8R-ZR9-Z96Z, sdk 0.1.0
[CleverTap] device id 5e1f7c90-...
[CleverTap] new session 1760871234
[CleverTap] event recorded: App Launched
[CleverTap] items in queue: 1
[CleverTap] sending to CleverTap: App Launched
[CleverTap] payload is 842 bytes
[CleverTap] POST https://eu1.clevertap-prod.com/a1?os=Roku&t=100&z=W8R-ZR9-Z96Z&ts=...
[CleverTap] payload [{"type":"meta",...}]
[CleverTap] response status 200, body {"status":"success",...}
```

Use the remote's arrow keys and **OK** to fire the SDK calls from the menu. Each one logs what
it recorded and what it sent. A send that worked logs nothing more, so silence after the
`sending to CleverTap:` line is the good case.

**Fire 3 events** records three events with no pause between them. The SDK waits one second
after the last recorded event before it sends, so all three go in a single request. The log
shows one `sending to CleverTap:` line naming all three.

### The login rows

The three rows at the top are named after the fields they send:

| Row | Fields sent | Matched on |
|-----|-------------|------------|
| **Login A - Email, Name** | `Email: sam@example.com`, `Name: Sam` | `Email` |
| **Login B - Email, Name** | `Email: bea@example.com`, `Name: Bea` | `Email` |
| **Login C - Name only, no identifier** | `Name: Cas`, `plan: free` | nothing |

Only `Identity`, `Email` and `Phone` identify a user, and the SDK reads them in that order, so
the first one present wins. Rows A and B send an `Email` and no `Identity`, so `Email` is what
they are matched on - an email address identifies a user on its own. `Name` never identifies
anyone, which is what row C is there to show.

Press them in this order to walk through all five outcomes of `onUserLogin`:

| Press | What happens | Device id |
|-------|--------------|-----------|
| **Login A**, on a device never identified before | the current id is claimed for A | unchanged |
| **Login A** again | already the current user, attributes only | unchanged |
| **Login B** | a different user with no id yet, so one is made. A's unsent items are dropped and a new session starts | **changes** |
| **Login A** again | A is known, so the id from the first press comes back | **changes** |
| **Login C** | no identifying field to look up, attributes land on whoever is current | unchanged |

The id at the end of the status line on screen is how you tell these apart.

The first row only behaves that way on a device where this channel has never identified
anyone. The claim is recorded permanently, so after it that row takes the fourth path
instead. Sideloading again does **not** reset this.

### Dates

**Push two dates of birth** sends a date the way an app has to send one. A date is written as
a map with one key, `date`. The value is either an ISO 8601 date and time, or a count of
seconds from 1 January 1970:

```brightscript
clevertap.callfunc("profilePush", [{ "DOB": { "date": "1990-04-17T00:00:00Z" } }])
clevertap.callfunc("profilePush", [{ "DOB": { "date": 640310400 } }])
```

The SDK converts it. In the payload the value appears as `"DOB":"$D_640310400"` - the number
of seconds from 1 January 1970, behind a prefix that marks the value as a date.

An `roDateTime` cannot be used here. Every call reaches the SDK through `callfunc`, and an
`roDateTime` does not survive that call. It arrives as nothing, and the attribute would be
sent empty. A map does survive, which is why the date is written as one.

An epoch number passed on its own is **not** treated as a date. The SDK cannot tell such a
number apart from a score or a price, so it leaves it alone. Use the map.

The row sends a second date, 3 March 1965, under the key `dobBefore1970`. It is written as a
second count rather than as text, so both forms are shown in one press. Dates before 1970
have a negative second count, and many real birth dates are in that range. Expect
`"dobBefore1970":"$D_-152496000"`. Anything else there means this device cannot hold dates
before 1970.

A date the device cannot read is reported and left out of the request, rather than sent as
1 January 1970:

```
[CleverTap] ERROR date for 'DOB' could not be read from '17 April 1990', so it was left out.
```

Problems are labelled:

```
[CleverTap] ERROR send failed with status 500, will try again: App Launched
```

`ERROR` is the only level that names itself. Everything else is ordinary progress, so marking
each line would just add noise.

## Log levels

The level is read from `sample/manifest`:

```
clevertap_log_level=debug
```

| Level | What you get |
|-------|--------------|
| `off` | nothing |
| `error` | only things that went wrong |
| `info` | what the SDK recorded and what it sent. The default. |
| `debug` | the above plus request URLs, full payloads, response bodies, queue depth |

Use `debug` while integrating. The full payload line is the one that answers "did we send the
right JSON", which is the question a real device can settle and a cloud device cannot.

An app can also pass `logLevel` to `init()`, which wins over the manifest:

```brightscript
clevertap.callfunc("init", { accountId: "...", token: "...", logLevel: "debug" })
```

Ship with `error`, or leave the key out to get `info`.

## After you change code

Re-run the same command, then sideload again:

```
npm run sample:zip
```

There is no separate "I only changed the sample" path. The command is fast and always
correct, which matters more than saving a few seconds.

### Why this is one command

The sample consumes the SDK as a packed tarball pinned to a version number. The version
rarely changes while the code does. npm compares its lockfile against that version, decides
nothing has changed, and skips the install. The sample keeps running an old copy of the SDK.

That failure is quiet. The zip builds, it sideloads, and it runs. It just runs yesterday's
code. If a module was added since the stale copy was taken, the channel instead crashes on a
function that does not exist, which sends you looking in the wrong place.

So `npm run sample:zip` deletes the lockfile and the installed copy every time, and then
checks the result: it compares every file in `source/` against the copy that landed in the
sample, and refuses to build the zip if they differ.

To check a zip you built earlier without building a new one:

```
node scripts/build-sample.js --check-only
```

## Troubleshooting

**`nc` connects but prints nothing.** The channel is not running. Relaunch it from the Roku
home screen, or sideload again. The console only prints while the channel is up.

**`nc: connection refused`.** The device is not in developer mode, or the IP is wrong, or
your computer is on a different network. A guest or IoT network will not reach it.

**The installer page asks for a password you do not have.** Repeat step 1 to set a new one.
Disabling and re-enabling developer mode factory-resets the sideloaded channel.

**No `[CleverTap]` lines at all.** Check `clevertap_log_level` in `sample/manifest` is not
`off`, and that `clevertap_account_id` and `clevertap_token` are filled in. Missing
credentials log one line and then the SDK stays inactive:

```
[CleverTap] ERROR missing account id or token, SDK inactive
```

**Events do not reach the dashboard.** Look for the `response status` line (it needs
`clevertap_log_level=debug`). A `200` means the SDK's side is done, and the gap is in the
account or the dashboard view.

**A negative status.** Anything below zero is not an HTTP status. The request never reached
the server, so the number is a curl error code from the device. The SDK logs the device's own
description next to it:

```
[CleverTap] ERROR POST to https://eu1.clevertap-prod.com/a1?... failed: Couldn't resolve host name (code -6)
[CleverTap] ERROR send failed with status -6, will try again: Product viewed
```

The ones you are most likely to see:

| Code | Means | Usual cause |
|------|-------|-------------|
| `-6` | the host name could not be turned into an address | no DNS. The device has no working internet, or is on a network that blocks it |
| `-7` | the address was found but refused the connection | a firewall or proxy in the way |
| `-28` | the connection ran out of time | a very slow or half-open network |
| `-35` / `-60` | the secure connection could not be set up | the device clock is wrong, or a proxy is intercepting HTTPS |
| `-1` | the SDK never got a reply at all | the request could not be started, or it ran past 30 seconds. A `timed out after 30s` line appears with it |

Except for `-1`, these numbers come from the device, not from the SDK. The batch stays in the
queue and goes out on the next try, so nothing is lost while the network is down.
