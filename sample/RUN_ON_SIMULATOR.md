# Run the sample in a browser simulator

A beginner-friendly guide to build this sample and run it in a free online Roku simulator.
No Roku device needed.

The simulator is [brs-engine](https://github.com/lvcabral/brs-engine), an open-source project
that runs Roku apps in the browser. You will build a channel `.zip` and drag it onto the
simulator page.

## What you need

- [Node.js](https://nodejs.org) installed. Check it in a terminal with `node -v`.
- This repository downloaded to your computer.
- A web browser (Chrome works well).

## 1. Build the sample

The sample uses the CleverTap SDK as a local package, so you first pack the SDK and let the
tooling copy it into the sample.

From the **repo root** (the folder that contains `source/`, `components/`, and `sample/`):

```
npm pack
```

That creates a file like `clevertap-roku-sdk-0.1.0.tgz` in the repo root.

Now move into the sample and assemble it:

```
cd sample
npm install
npx ropm install
```

- `npm install` downloads the tooling and unpacks the SDK.
- `npx ropm install` copies the SDK into `source/roku_modules/` and `components/roku_modules/`
  so the channel can find it.

## 2. Zip the channel

Still inside the `sample` folder, run the command for your system. Running it from **inside**
`sample` is important, because Roku expects `manifest` at the top of the zip.

macOS or Linux:

```
zip -r ../clevertap-roku-sample.zip manifest source components images
```

Windows (PowerShell):

```
Compress-Archive -Path manifest,source,components,images -DestinationPath ..\clevertap-roku-sample.zip
```

Either way you get `clevertap-roku-sample.zip` one folder up (in the repo root).

## 3. Add your credentials (optional for a first run)

Open `sample/manifest` and fill in your CleverTap `clevertap_account_id`, `clevertap_token`,
and `clevertap_region`, then rebuild the zip (step 2). You can skip this the first time just
to see the app boot. See the note about networking below.

## 4. Run it in the simulator

1. Open [https://lvcabral.com/brs](https://lvcabral.com/brs) in your browser.
2. Drag `clevertap-roku-sample.zip` onto the page (or use the page's file picker).
3. The sample boots and shows a menu of SDK calls.

## Controls (your keyboard acts as the Roku remote)

- **Arrow keys** - move up and down the menu.
- **Enter** - OK / select. Fires the highlighted SDK call.
- **Escape** - back.

## Seeing the output

A few places to look, depending on what you want to check.

**Console (prints and errors).** Open DevTools *before* you load the zip - press **F12**, or
right-click the page and choose **Inspect**, then open the **Console** tab. Prints only show
up if DevTools is already open when the app loads, and engine exceptions appear here too. The
SDK stays quiet on the normal path, so a successful call may print nothing.

**Network tab (the actual upload).** About a second after you fire a call, the SDK uploads
over HTTP. Open **DevTools -> Network** and look for a POST to your region host (with
`clevertap_region=in1` in the manifest, that's `in1.<clevertap-domain>`). That request is
carrying your events.

**Application -> Local Storage (device id / GUID and the queue).** The SDK keeps its durable
state in the Roku registry, which the simulator stores in the browser's Local Storage. Open
**DevTools -> Application -> Local Storage** and pick the simulator's entry. The SDK's registry
section is named `clevertap_<your account id>` and the device GUID is stored under the key
`deviceId`, so search the entries for `deviceId` or `clevertap` to find it. That value is the
anonymous device id CleverTap shows on a "Not Identified" profile until you run Login user.

## Good to know

- **The menu may look rough.** SceneGraph support in the simulator is still beta, so the UI
  might not render perfectly. Booting and the console output are the reliable parts.
- **Events do reach your CleverTap dashboard from the browser.** CleverTap's endpoint accepts
  the cross-origin request, so the upload goes through from the simulator - events and their
  properties show up in the dashboard, attached to the anonymous device profile until you fire
  Login user to identify it. For a fully device-accurate run you can still sideload to a real
  Roku (see [README.md](README.md)), but it isn't required just to confirm events land.

## After you change code

Run this from the repo root instead of repeating steps 1 and 2:

```
npm run sample:zip
```

It packs the SDK, reinstalls it into the sample, checks the sample really got your current
code, and writes the zip. Then drag the new zip onto the simulator.

Do not refresh the sample by hand. The SDK version number does not change between builds, so
npm compares its lockfile against that version, decides nothing has changed, and skips the
install. The sample then keeps running an old copy of the SDK, and nothing warns you: the zip
builds and the channel boots. Deleting `node_modules/clevertap-roku-sdk` is not enough on its
own, because `sample/package-lock.json` still records the old package and npm can restore it
from its cache. `npm run sample:zip` removes both, every time, and then verifies the result.
