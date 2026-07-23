# Getting Started

### Configure Enforce

To configure Enforce, you initialize a new ``Config`` structure and provide your client name.

```swift
import CheqEnforce

Enforce.configure(Config("demoretail", publishPath: "mobile_privacy_sdk", environment: "English"))
```

While developing, you can enable debug to print log messages to the console that include information about the translations and consent options from Enforce.
> Remember to disable this when releasing your application.

```swift
import CheqEnforce

Enforce.configure(Config("demoretail", publishPath: "mobile_privacy_sdk", environment: "English", debug: true))
```

### Checking Consent Status

Use checkConsent(_:) to verify whether a user has granted consent for a specific category:

```swift
let hasAnalytics = Enforce.checkConsent("Analytics")
if hasAnalytics {
    // Enable analytics tracking
} else {
    // Disable analytics
}
```

### Retrieving Stored Consent

All categories

```swift
let allConsent: [String: Bool] = Enforce.getConsent()
// returns ["Analytics": true, "Marketing": true, "Functional": true]
```

Single category

```swift
let marketingConsent: [String: Bool] = Enforce.getConsent(for: "Marketing")
// returns ["Marketing": true]
```

Multiple categories

```swift
let subset = Enforce.getConsent(for: ["Analytics", "Functional"])
// returns ["Analytics": false, "Functional": true]
```

### Updating Consent Manually

Overwrite or merge new consent values using:

```swift
Enforce.setConsent([
    "Analytics": true,
    "Marketing": false
])
```

> **Note:** You must have called configure(_:) first; otherwise the SDK logs an error.

### Clearing Consent

Use `clearConsent()` to programmatically remove all stored consent, reverting the user to a "no consent" state. This is useful for flows such as logout, account switch, or an in-app "reset privacy" action.

```swift
Task {
    await Enforce.clearConsent()
}
```

Calling this deletes the persisted consent record, notifies every `onConsent(_:)` subscriber with an empty map, and dismisses any visible consent banner or modal.

After clearing:
- `getConsent()` returns `[:]`
- `checkConsent(category)` returns `false` for all categories
- On the next `configure(_:)` call, the SDK finds no stored consent and follows its normal auto-show logic (banner or modal, depending on remote config).

### Changing Environment at Runtime

If you need to switch environments without rebuilding:

```swift
Task {
  do {
    try await Enforce.setEnvironment("staging")
    print("Environment switched successfully")
  } catch {
    print("Failed to switch environment:", error)
  }
}
```
This updates the stored Config.environment and will affect subsequent UI fetches.

> **Note:** On failure, the environment is reverted to its previous value.

### Manual UI Control
If you want to show the banner or modal on demand (e.g., from a settings screen):

```swift
// Show the consent banner immediately
Enforce.showBanner()

// Show the consent modal immediately
Enforce.showModal()
```

### `onConsent` Callback

Enforce’s `onConsent` API lets you register one or more callbacks that will be invoked whenever consent settings change as well as on start up if consent is already available. Each callback receives the full, up-to-date consent dictionary.

```swift
Enforce.onConsent { consent in
    print("onConent: \(consent)")
}
```

### Customizing the UI with a Theme

Supplying an ``EnforceTheme`` in your ``Config`` switches the consent banner to a custom bottom sheet that slides up from the bottom of the screen, and applies your colors, fonts, and logo to both the banner and the consent modal. Without a theme, the SDK keeps its default system alert banner.

**Recommended: bundle a theme file.** Add a file named `enforce_theme.json` to your app target (the same theme document works with the web and Android SDKs) and load it when configuring:

```json
{
  "banner": {
    "backgroundColor": "#FFFFFF",
    "buttons": {
      "acceptAll": { "backgroundColor": "#1E478F", "textColor": "#FFFFFF", "borderRadius": 8 },
      "global":    { "backgroundColor": "#EBEBEB", "textColor": "#000000", "borderRadius": 8 }
    }
  },
  "modal": {
    "presentationStyle": "card",
    "categories": { "toggleOnColor": "#1E478F", "toggleOffColor": "#D9D9D9" }
  }
}
```

The modal's `presentationStyle` is `"card"` (a centered card over a dimmed background, the default) or `"fullScreen"` (covers the entire screen).

```swift
let theme = try EnforceTheme(bundleFile: "enforce_theme")
Enforce.configure(Config("demoretail", publishPath: "mobile_privacy_sdk", environment: "English", theme: theme))
```

`EnforceTheme(bundleFile:bundle:)` throws if the file is missing or malformed; `EnforceTheme(contentsOf:)` loads from any file URL.

**Alternatively, build the theme in Swift:**

```swift
let theme = EnforceTheme(
    banner: EnforceTheme.Banner(
        logoAlignment: .center,
        backgroundColor: "#FFFFFF",
        buttons: EnforceTheme.BannerButtons(
            acceptAll: EnforceTheme.ButtonStyle(backgroundColor: "#1E478F", textColor: "#FFFFFF", borderRadius: 8),
            global: EnforceTheme.ButtonStyle(backgroundColor: "#EBEBEB", textColor: "#000000", borderRadius: 8)
        ),
        logoUIImage: UIImage(named: "BrandLogo")
    ),
    modal: EnforceTheme.Modal(
        categories: EnforceTheme.Categories(toggleOnColor: "#1E478F", toggleOffColor: "#D9D9D9")
    )
)

Enforce.configure(Config("demoretail", publishPath: "mobile_privacy_sdk", environment: "English", theme: theme))
```

Key points:
- Every value is optional. A missing button value falls back to the `global` button style, then to a light-mode default.
- Colors are hex strings (`"#RRGGBB"` or `"#RRGGBBAA"`); invalid values are logged and fall back to defaults.
- The logo can be supplied as a `UIImage` (`logoUIImage`), an asset-catalog name (`logoImage`), or a remote URL (`logoURL`), in that order of precedence, and aligned `left`, `center`, `right`, or `full`.
- Because `EnforceTheme` is `Codable`, it can also be decoded from a JSON document shared with the web and Android SDKs.

> **Note:** Themed UI is light-mode based. When a theme is present, the `appearance` setting is ignored (a log message notes this).

For the complete list of theme keys, types, defaults, and cross-platform conventions, see <doc:ThemeReference>.

### Building Your Own Consent UI

If you want to render the consent experience yourself, use `getConfiguration()` to access the translations and button configuration fetched from the remote JSON file:

```swift
if let configuration = Enforce.getConfiguration() {
    let bannerText = configuration.translation.notificationBannerContent
    let showAcceptAll = configuration.bannerConfig?.ensAcceptAll == true
    // Render your own UI, then persist the user's choice:
    Enforce.setConsent(["Analytics": true, "Marketing": false])
}
```

> **Note:** `getConfiguration()` returns `nil` until `configure(_:)` has finished its asynchronous fetch.
