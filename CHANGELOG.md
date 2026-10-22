# Change Log
All notable changes to this project will be documented in this file.

### Version 0.1.0 (Unreleased)
#### Added
- **Initial Release:** The CleverTap Roku SDK provides analytics for Roku channels written in BrightScript and SceneGraph. The SDK is a SceneGraph node named `CleverTap`, and every call is made on it through `callfunc`.
    * `init(config)` configures the SDK and must be called once before anything else. `config` carries `accountId`, `token` and `region`, and optionally `proxyDomain` and `logLevel`. Pass an empty object to take all of them from the channel manifest.
    * `recordEvent([name, properties])` records a custom event. `properties` is optional.
    * `recordChargedEvent([details, items])` records a purchase as a `Charged` event. `details` carries `Amount`, and `items` is the array of line items.
    * `onUserLogin([profile])` identifies a user. The identity is taken from `Identity`, `Email` or `Phone`, and the remaining keys are set as profile attributes.
    * `profilePush([profile])` sets system and custom attributes on the current user.
    * `getCleverTapID()` returns the current CleverTap ID, so a channel session can be matched to its dashboard profile.
- **Profile Commands:** Eight calls that change one profile property instead of replacing it. Each takes its arguments as `[key, value]`.
    * `profileRemoveValueForKey([key])` removes a property from the profile.
    * `profileSetMultiValues([key, values])` replaces the whole list of a multi-value property.
    * `profileAddMultiValue([key, value])` and `profileAddMultiValues([key, values])` put values into that list.
    * `profileRemoveMultiValue([key, value])` and `profileRemoveMultiValues([key, values])` take values out of that list.
    * `profileIncrementValueBy([key, amount])` and `profileDecrementValueBy([key, amount])` move a number property. The amount must be above zero.
    * **Note:** A multi-value property holds text, so a number is converted, and at most 100 values are kept. The SDK holds no local copy of the profile, so a command is applied by the server and no property can be read back on the device.
- **App Launched:** The SDK records an `App Launched` event at the start of every session.
- **Sessions:** Sessions are started and ended by the SDK. A session ends after 20 minutes without a recorded event, and survives the channel closing and reopening.
- **Delivery:** Network calls run on a background task, so the render thread is never blocked. Events recorded close together are sent in one request. Unsent items are stored on the device and sent when the network returns, and a failed send is retried with a backoff of up to 60 seconds.
- **Configuration from the Manifest:** `clevertap_account_id`, `clevertap_token`, `clevertap_region` and `clevertap_log_level` can be set in the channel manifest instead of in code. A value passed to `init()` wins over the manifest.
- **Logging:** Four levels, `off`, `error`, `info` and `debug`, printed to the BrightScript debug console.
- **Input Validation:** Empty, over-long and reserved event names are rejected. Empty and over-long profile keys are dropped. A key that matches a reserved name apart from its letter case is reported, which on Roku catches an unquoted `Amount` or `Identity` being lower-cased by BrightScript before the SDK sees it.
