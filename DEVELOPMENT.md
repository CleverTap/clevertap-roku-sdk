# Developing the CleverTap Roku SDK

This is for engineers working on the SDK itself. If you are integrating the SDK into a
channel, see the [README](README.md) instead.

## Setup

Requires Node.js. Install the tooling:

```
npm install
```

## Build

```
npm run build
```

Type-checks the `source/` and `components/` files with the BrighterScript compiler (`bsc`).

## Test

```
npm test
```

Runs the unit suite headlessly with the [brs](https://github.com/sjbarag/brs) interpreter, so
no Roku device is needed. The pure logic - device, session, queue, validation, request
building, networking decisions, profile, and login - is covered here. The SceneGraph node
wiring (the `CleverTap` node and its upload Task) is verified by sideloading the sample
against a test account.

Both commands run in CI on every push and pull request.
