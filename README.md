Fit3D Importer for Apple Health
===============================

An iOS app to import Fit3D scans into Apple Health.

1. Uses `WKWebView` to authenticate to the Fit3D API and obtain an API token.  At no point are your credentials observed, accessed, or saved.
2. Downloads all available scan data from the Fit3D API.
3. Identifies and saves all Fit3D data that can be modeled in `HealthKit`.  Duplicates are detected and ignored, so this is safe to use when importing new scans in the future.