# Build Delight APK for Mobile Testing

## Prerequisites
Make sure you have Flutter installed and android SDK set up.

## Step 1 — Set up Firebase for push notifications

1. Go to: https://console.firebase.google.com
2. Create project: "Delight Africa"
3. Add Android app:
   - Package name: `africa.delight.app`
   - App nickname: Delight
   - Download `google-services.json`
   - Place it at: `android/app/google-services.json`
4. Enable Cloud Messaging in Firebase console

## Step 2 — Build the debug APK (for testing)

```bash
cd ~/Videos/delight-app/delight

# Get packages
flutter pub get

# Build APK (debug — no signing needed for testing)
flutter build apk --debug

# APK location after build:
# build/app/outputs/flutter-apk/app-debug.apk
```

## Step 3 — Install on your phone

### Option A — USB cable
```bash
# Enable Developer Options on your phone:
# Settings → About Phone → tap Build Number 7 times
# Settings → Developer Options → enable USB Debugging

# Connect phone via USB, then:
flutter install
# OR
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### Option B — Transfer the APK file
```bash
# Copy APK to a location you can share
cp build/app/outputs/flutter-apk/app-debug.apk ~/Desktop/delight-test.apk

# Then:
# - Email it to yourself
# - Upload to Google Drive
# - Transfer via USB
# - Open on phone → Allow unknown sources → Install
```

## Step 4 — For release APK (smaller, faster)
```bash
flutter build apk --release

# APK at: build/app/outputs/flutter-apk/app-release.apk
```

## If build freezes your PC
Build on phone resources, not PC render:
```bash
# Limit Gradle memory usage
export GRADLE_OPTS="-Xmx1536m"
flutter build apk --debug --no-shrink
```

## What to test on mobile
- [ ] Login / signup with real email
- [ ] Balance shows R9,500 (1000 DC testnet)
- [ ] GPS agent finder — shows nearest agents
- [ ] Send money to another test account
- [ ] Buy a ticket from events
- [ ] NFT ticket card appears in My Tickets
- [ ] Share ticket to Instagram (copies caption)
- [ ] Cash out flow (testnet — no real bank transfer)
- [ ] Push notification on payment received
- [ ] QR scanner for payments
- [ ] Dark theme renders correctly
