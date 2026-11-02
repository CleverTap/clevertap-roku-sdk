# Developing the CleverTap Roku SDK

This is for engineers working on the SDK itself. If you are integrating the SDK into a
channel, see the [README](README.md) instead.

## Setup

Node.js 20, which is what CI uses. `package.json` does not pin a version, so an older Node
may give different `bsc` results.

```
npm install
```

## Where things live

| Path | What it holds |
|---|---|
| `source/` | The SDK's logic. Plain BrightScript functions, no SceneGraph. Device, session, queue, validation, request building, networking decisions, profile, login, values, time zones. This is what the unit suite covers. |
| `components/` | The SceneGraph layer. `CleverTap` is the public node an app creates. `CleverTapTask` makes the network calls, so the render thread is never blocked. |
| `test/` | The off-device suite. `test/support/` holds the harness and the platform fakes. |
| `scripts/` | `run-tests.js` and `build-sample.js`. |
| `sample/` | A runnable channel with a menu that fires every public call. |

A SceneGraph component does not see `pkg:/source` by itself. Every module a node uses is
listed as a `<script>` tag in that node's XML. A new file in `source/` has to be added to
`components/CleverTap.xml` before the node can call anything in it.

## Build

```
npm run build
```

Type-checks `source/` and `components/` with the BrighterScript compiler (`bsc`). It does not
look at `sample/`.

## Test

```
npm test
```

Runs the suite headlessly with the [brs](https://github.com/sjbarag/brs) interpreter, so no
Roku device is needed. Expect `TESTS PASSED: <n>` at the end.

### A green run is not enough

`brs` is not Roku firmware. One divergence is known and it matters.

`brs` keeps the letter case of an unquoted key in an associative array literal. Real firmware
lowercases it. So `{ Amount: 300 }` keeps its capital A under test. On a device the same line
becomes `amount`, and the server stops reading it as the purchase value. The test passes. The
revenue is wrong.

A whole class of wire bugs is invisible to this suite. Sideload the sample and read the
payload before trusting any change to what goes on the wire. See
[sample/RUN_ON_DEVICE.md](sample/RUN_ON_DEVICE.md) for that setup.

### Adding a test

1. Create `test/CleverTapThingTests.brs` holding a function of the same name:
   `function CleverTapThingTests(t as object)`. The runner globs `test/**/*Tests.brs`, so the
   file is found on its own.
2. Add one call to it in `test/CleverTapTestMain.brs`. This is the step that is easy to
   forget. Without it the file is still parsed, the suite still passes, and nothing in it ran.

Three assertions exist. They are in `test/support/CTTest.brs`:

```brightscript
t.eq(actual, expected, "what this proves")
t.isTrue(value, "what this proves")
t.isFalse(value, "what this proves")
```

`t.eq` compares the two values by their `FormatJson` form. That covers numbers, strings,
arrays and maps with one assertion.

`test/support/CTFakes.brs` holds stand-ins for `roDeviceInfo` and `roAppInfo`. Each answers
only the methods the SDK calls, with fixed values, so a test never depends on the machine it
runs on. Add a fake there rather than inside a suite.

A test that makes the SDK log should turn the console copy off around itself:

```brightscript
CleverTapLogSetConsoleOutput(false)
' ... the part that logs ...
CleverTapLogSetConsoleOutput(true)
```

Hundreds of generated lines otherwise bury the result.

## The sample channel

```
npm run sample:zip
```

This is the real gate before a commit. It runs the unit suite, type-checks, packs the SDK,
reinstalls it into the sample, checks the sample really got the current code, and only then
writes the zip. If any step fails, no zip is written.

Do not assemble the sample by hand. It silently leaves the channel on a stale copy of the
SDK. [sample/README.md](sample/README.md) explains why, and
[sample/RUN_ON_SIMULATOR.md](sample/RUN_ON_SIMULATOR.md) covers running it without a device.

## CI

`npm run build` and `npm test` run on every pull request, and on every push to `main`. A push
to a feature branch does not trigger them, so open the pull request to get a CI run.

## Release

The SDK publishes to npm. ropm has no registry of its own, so `ropm install
clevertap-roku-sdk` installs the npm package and renames what it copies into a channel.

One part of that is worth knowing outside a release, because it breaks the build. The version
number in `package.json` is also written into `sample/package.json`, which depends on
`file:../clevertap-roku-sdk-<version>.tgz`. Change one without the other and
`npm run sample:zip` fails, because `npm pack` wrote a file under a different name.
