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
zip -r ../clevertap-roku-sample.zip manifest source components
```

Windows (PowerShell):

```
Compress-Archive -Path manifest,source,components -DestinationPath ..\clevertap-roku-sample.zip
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

Open your browser's developer console to watch what the SDK prints when you fire a call:
press **F12**, or right-click the page and choose **Inspect**, then open the **Console** tab.

## Good to know

- **The menu may look rough.** SceneGraph support in the simulator is still beta, so the UI
  might not render perfectly. Booting and the console output are the reliable parts.
- **Events will not reach your CleverTap dashboard from the browser.** A browser tab blocks
  the kind of network request the SDK makes, so the upload will not go through here. The
  simulator is good for "does it boot and run", not for confirming events land. For real
  end-to-end verification, sideload the channel to an actual Roku device (see
  [README.md](README.md)).

## After you change code

If you edit the SDK or the sample, rebuild: run `npm pack` in the repo root again, then
`npx ropm install` in `sample`, then redo the zip in step 2.
