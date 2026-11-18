# Delight Android Setup

## Your App Package Name
```
africa.delight.app
```
Use this EXACTLY when creating your Android OAuth Client in Google Cloud Console.

## Getting your SHA-1 (run this on your machine)
```bash
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey \
  -storepass android \
  -keypass android
```
Copy the SHA1 line — looks like: A1:B2:C3:D4:E5:F6:...

## Steps to complete Android setup
1. Get SHA-1 from command above
2. Google Cloud Console → Credentials → Create Android OAuth Client
   - Package name: africa.delight.app  
   - SHA-1: paste from above
3. Download google-services.json → replace android/app/google-services.json
4. In android/build.gradle, uncomment:
   classpath 'com.google.gms:google-services:4.4.1'
5. In android/app/build.gradle, add at bottom of plugins block:
   id "com.google.gms.google-services"
6. In android/app/src/main/res/values/strings.xml, replace:
   YOUR_WEB_CLIENT_ID with your actual Web Client ID
7. flutter run (connects to Android emulator or device)

## File structure created
android/
├── app/
│   ├── build.gradle              ← applicationId "africa.delight.app"
│   ├── google-services.json      ← REPLACE with real file from Google
│   ├── proguard-rules.pro
│   └── src/
│       ├── main/
│       │   ├── AndroidManifest.xml
│       │   ├── kotlin/africa/delight/app/MainActivity.kt
│       │   └── res/
│       │       ├── drawable/launch_background.xml
│       │       ├── values/strings.xml   ← put your Web Client ID here
│       │       ├── values/styles.xml
│       │       └── xml/network_security_config.xml
│       ├── debug/AndroidManifest.xml
│       └── profile/AndroidManifest.xml
├── build.gradle
├── gradle.properties
├── gradle/wrapper/gradle-wrapper.properties
├── local.properties              ← update sdk.dir and flutter.sdk paths
└── settings.gradle
