# Windows dependency compatibility patches

These copies retain their upstream licenses.

- flutter_secure_storage_windows 4.1.0: replace ATL-only CA2W/CW2A conversions with owned UTF-8/UTF-16 conversions using MultiByteToWideChar and WideCharToMultiByte. Encryption, Windows credential storage, and key management remain upstream code.
- flutter_local_notifications_windows 3.0.0: replace three ATL CW2A conversions with winrt::to_string and handle a null activation payload.

The installed Visual Studio C++ tools lacked the optional ATL headers. These small source adaptations avoid changing the user's system installation. Native Windows integration tests exercised secure pairing persistence and notification schedule/cancel behavior after the patches.

Review these overrides before upgrading upstream package versions.
