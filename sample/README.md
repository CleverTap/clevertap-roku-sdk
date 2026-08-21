# CleverTap Roku sample

A small Roku channel that starts the SDK and shows a menu of its calls. Highlight a row and
press OK to fire that one call, so you can check it against a test CleverTap account.

Want to try it without a Roku device? See [RUN_ON_SIMULATOR.md](RUN_ON_SIMULATOR.md) for the
free browser simulator. The steps below are for running it on a real Roku.

## Build the sample

The sample uses the SDK as a local package and lets a tool called
[ropm](https://github.com/rokucommunity/ropm) copy the SDK files into place for you.

From the repo root:

```
npm pack            # packages the SDK into a .tgz file in the repo root
cd sample
npm install         # downloads the tooling and unpacks the SDK
npx ropm install    # copies the SDK into the sample so the channel can find it
```

Run `npm pack` first, because the sample points at that packaged file. Whenever you change the
SDK, run `npm pack` and `npx ropm install` again. The files these commands generate are
throwaway build output, so they are not committed.

One thing to know: ropm renames the SDK's node using the package name, so in code the sample
creates `clevertaprokusdk_CleverTap` instead of plain `CleverTap`. That is already set up in
`MainScene.brs`, so you do not need to change anything.

## Run it on a Roku

1. Put your CleverTap credentials in `manifest` (or pass them to the `init()` call in
   `MainScene.brs`).
2. Zip the `manifest`, `source`, `components`, and `images` together, then load that zip onto a
   Roku that is in Developer Mode.
3. Use the remote to highlight a row and press OK to fire that call.
4. Check that the event, purchase, identified user, or profile shows up in your CleverTap
   dashboard. You can also watch the channel's debug log (over telnet, port 8085) to see each
   request go out.
