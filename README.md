# Kwarta Budget Tracker — Native Android (Flutter)

A phone-first Android budget tracker based on the supplied Cebuano Budget Tracker.

## What it does

- Records income and expenses in Philippine pesos.
- Stores every record locally in SQLite before attempting cloud sync.
- Lets the user add, view, and soft-delete records while offline.
- Tracks monthly spending and a monthly budget limit.
- Breaks expenses down by category.
- Syncs pending records and monthly budgets to Supabase when a connection is available.
- Keeps each user's data scoped to their Supabase account.

## Stack

- Flutter / Dart
- SQLite via `sqflite` for on-device storage
- Supabase Auth + PostgreSQL for sign-in and cloud backup
- `connectivity_plus` to notice network changes

## Supabase setup

The application is configured to use the existing Supabase project:

- Project URL: `https://edidurmeizrdysihvhdl.supabase.co`
- Public client key: the Supabase publishable key in `lib/main.dart`

The publishable key is intended for client apps. Do not replace it with a `service_role` or secret key. The database tables use Row Level Security so records are restricted to the signed-in account.

The tables `budget_transactions` and `monthly_budgets` have already been created in the user's existing Supabase project. The matching SQL is included in `supabase/schema.sql` for reference or a new project setup.

In Supabase Dashboard, make sure email/password sign-up is enabled under Authentication > Providers > Email. If email confirmation is enabled, new users must confirm their email before signing in.

## Build the APK on Windows

1. Install Flutter and Android Studio (with Android SDK and Android SDK Platform Tools).
2. Extract this ZIP.
3. Open the extracted `kwarta_budget_android` folder in VS Code or Android Studio.
4. The build script first checks Flutter in PATH, then checks your existing `D:\flutter\src\flutter\bin\flutter.bat` installation. In the terminal, `flutter doctor` should show Android toolchain available.
5. Double-click `BUILD-APK.bat`, or run the commands below from the project folder.

```powershell
flutter create --platforms=android --org com.reaamparo --project-name kwarta_budget_tracker .
flutter pub get
flutter build apk --release
```

The APK will be created at:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Copy that APK to your Android phone and open it to install. You may need to allow your browser or file manager to install apps from that source.

## First use and offline use

- The first sign-in or account creation requires internet.
- After signing in once, the Supabase session is persisted by the Flutter Supabase client.
- Records and monthly budgets are written to SQLite first.
- When internet returns, pending writes are sent to Supabase and remote records are downloaded.
- Signing out does not erase local SQLite data. Local data is separated by user ID.

## Important limitations

- This is a native Android Flutter project, not a website or PWA.
- A release APK has not been compiled in this build environment because the Flutter SDK and Android SDK are not installed here. Use `BUILD-APK.bat` on a Windows machine with Flutter and Android Studio installed to generate the installable APK.
- Offline mode requires the app and account to have been initialized online at least once. First-time registration/login cannot work without internet.
- Connectivity status is only an indication; sync failures are caught and the pending local records remain saved for retry.
