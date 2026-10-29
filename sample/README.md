# CleverTap Roku sample

A small Roku channel that starts the SDK and shows a menu of its calls. Highlight a row and
press OK to fire that one call, so you can check it against a test CleverTap account.

Two ways to run it:

- On a real Roku: [RUN_ON_DEVICE.md](RUN_ON_DEVICE.md). This is the only setup that can check
  what the SDK actually sends.
- Without a device: [RUN_ON_SIMULATOR.md](RUN_ON_SIMULATOR.md), a free browser simulator.

## Build the sample

From the repo root:

```
npm run sample:zip
```

That is the whole build. It packs the SDK, copies it into the sample, checks the sample
really got your current code, and writes `clevertap-roku-sample.zip` in the repo root. Run it
again after every change. Everything it generates is throwaway build output, so none of it is
committed.

Do not assemble the sample by hand with `npm pack` and `npx ropm install`. The SDK version
number does not change between builds, so npm decides the already-installed copy is current
and skips the install, leaving the sample on an old copy of the SDK. The build script works
around that and then verifies the result. See "Why this is one command" in
[RUN_ON_DEVICE.md](RUN_ON_DEVICE.md).

One thing to know: [ropm](https://github.com/rokucommunity/ropm) renames the SDK's node using
the package name, so in code the sample creates `clevertaprokusdk_CleverTap` instead of plain
`CleverTap`. That is already set up in `MainScene.brs`, so you do not need to change anything.

## Then

1. Put your CleverTap credentials in `manifest` (or pass them to the `init()` call in
   `MainScene.brs`).
2. Sideload the zip onto a Roku that is in Developer Mode.
3. Use the remote to highlight a row and press OK to fire that call.
4. Check that the event, purchase, identified user, or profile shows up in your CleverTap
   dashboard. You can also watch the channel's debug log (port 8085) to see each request go
   out.
