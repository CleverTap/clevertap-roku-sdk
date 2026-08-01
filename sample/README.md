# CleverTap Roku sample

A minimal channel that starts the SDK and shows a menu of its public calls. Press OK on a
row to fire that one call, for manual end-to-end verification against a test CleverTap
account.

## Assemble and run

The sample needs the SDK's `source/` and `components/` files alongside its own. Either:

- **ropm (recommended):** run `ropm install clevertap` in this folder, which pulls the SDK
  in under the `clevertap` namespace, then update `MainScene.brs` to create the node with
  its namespaced name; or
- **quick local test:** copy the repo's `source/` and `components/` files into this folder's
  `source/` and `components/` so `CleverTap` and `CleverTapTask` are registered.

Then set your credentials (either in `manifest` or in the `init()` call inside
`MainScene.brs`), zip the folder, and sideload it to a Roku in Developer Mode. Use the remote
to select a row and press OK to fire that call. Watch the debug console (telnet port 8085)
for the outgoing request and confirm the event, purchase, identified user, or profile appears
in the CleverTap dashboard.
