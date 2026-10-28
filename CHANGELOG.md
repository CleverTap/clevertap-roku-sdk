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
- **Dates:** `DOB`, `Birthday`, any custom profile attribute and any event property can hold a date. A date is written as a map with one key, `{ "DOB": { "date": "1990-04-17T00:00:00Z" } }` or `{ "DOB": { "date": 640310400 } }`. The SDK sends it as `$D_` followed by the number of seconds from 1 January 1970, and a date before 1970 keeps its negative count. An `roDateTime` cannot be used, because it does not survive the `callfunc` into the SDK node. A number passed on its own stays a number, because the SDK cannot tell a second count apart from a score or a price. A date the device cannot read is reported and left out of the request, so it never replaces a date the server already holds.
- **Phone Numbers:** `Phone` is reported when it cannot be dialled as given. A number is reported when it is not written as text, because a number cannot hold a leading `+` or a leading zero. It is also reported when it carries no country code and the device reports no country to complete it from. Both are reports only, and the value is always sent.
- **Device Fields:** The SDK reports the device model, maker, OS version, screen size and locale with every batch.
- **Country and Time Zone:** The SDK sets the `cc` and `tz` profile attributes from the device once per launch, which is where the dashboard reads them from and where the mobile SDKs put them. The country also rides in the device fields of every batch, again matching the mobile SDKs. Either one is left out when the device does not report it.
    * The country comes from the Roku account's store. Roku returns `OT` when it does not know the country, and names a partner such as `skyuk` when the account was opened through one. `OT` is left out, a partner name is read as its country, and any other value that is not a two-letter code is left out rather than sent as a country.
    * Roku has its own name for each time zone, such as `Europe/United Kingdom`, and the name is sent as the device gives it.
- **Server Response Values:** Every reply carries an `arp` block. The SDK saves it against the current device id and repeats it in the header of every later request, which is what the mobile SDKs do. A value that arrives replaces the one held under the same name, and a name the server sends as `-1` is dropped rather than repeated.
    * The `d_e` name inside that block lists the events switched off in the dashboard. Those events are no longer queued or sent, which saves a request the server would only throw away. The list is held for the run and is not saved, because the server sends it again with every reply.
- **App Launched:** The SDK records an `App Launched` event at the start of every session.
- **Sessions:** Sessions are started and ended by the SDK. A session ends after 20 minutes without a recorded event, and survives the channel closing and reopening.
- **Delivery:** Network calls run on a background task, so the render thread is never blocked. Events recorded close together are sent in one request. Unsent items are stored on the device and sent when the network returns, and a failed send is retried with a backoff of up to 60 seconds.
- **Configuration from the Manifest:** `clevertap_account_id`, `clevertap_token`, `clevertap_region` and `clevertap_log_level` can be set in the channel manifest instead of in code. A value passed to `init()` wins over the manifest.
- **Logging:** Four levels, `off`, `error`, `info` and `debug`, printed to the BrightScript debug console.
- **Input Validation:** Empty, over-long and reserved event names are rejected. Empty and over-long profile keys are dropped. A key that matches a reserved name apart from its letter case is reported, which on Roku catches an unquoted `Amount` or `Identity` being lower-cased by BrightScript before the SDK sees it.
