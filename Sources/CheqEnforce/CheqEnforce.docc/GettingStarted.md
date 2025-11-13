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
