# Do you need this folder at all?
Only for guests WITHOUT the app. Inside the app nothing here is used.
- No domain to buy: upload this folder to Cloudflare Pages / Netlify / GitHub Pages and use the free
  address they give you (e.g. delight.pages.dev). Then:
    * change the android:host values in AndroidManifest.xml to that address, and
    * build the app with --dart-define=LINK_HOST=delight.pages.dev
- Skip it entirely: invitations then only work for people who already have the app, and only if you
  share the link inside a chat that makes it clickable (WhatsApp only links http/https, not delight://).

# delight.africa link pages (RSVP + pay links)

What this does
- App installed: tapping https://delight.africa/rsvp/<id> (or /pay/<id>) opens the Delight app straight
  on the invitation / pay screen (Android App Links). Signed-out guests see the RSVP form.
- App not installed: the browser loads this small site, which shows the invite name/date and a
  "Get the app" button (Play Store on Android, App Store on iPhone).

Why your link showed "This site can't be reached" (DNS_PROBE_FINISHED_NXDOMAIN)
  delight.africa has no DNS record yet. The app cannot fix that: you need to own the domain and
  host this folder on it.

One-time setup
1. Domain: register delight.africa (or whichever domain you want) and host THIS folder on it.
   Easiest free option: Cloudflare Pages or Netlify -> "Deploy a folder" -> upload web-links/ ->
   add the custom domain and follow its DNS instructions. HTTPS is automatic.
2. web-links/config.js: paste your Supabase anon key (Supabase -> Project Settings -> API).
   Set appStore once the iPhone app exists.
3. Android verification (this is what makes links open the app without a chooser):
   - Get the SHA-256 of the key that signs the installed app:
       Play Store builds: Play Console -> Setup -> App signing -> "App signing key certificate" SHA-256.
       Debug builds:      keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
   - Put it in web-links/.well-known/assetlinks.json (replace REPLACE_WITH_YOUR_SHA256_FINGERPRINT).
   - Check: https://delight.africa/.well-known/assetlinks.json must open in a browser and show the JSON.
   - Rebuild and reinstall the app (the manifest now declares the links).
4. Test: send yourself the link in WhatsApp and tap it.
   Without step 3 the app can still open from the web page's "Open in Delight" button (delight:/// link).

iPhone (later, needs an iOS project and an Apple developer account)
- Replace REPLACE_TEAMID in .well-known/apple-app-site-association with your Apple Team ID.
- In Xcode: Runner -> Signing & Capabilities -> + Associated Domains -> applinks:delight.africa
- This repo has no ios/Runner files yet, so that part is not done.

Until the app is on the Play Store, "Get the app" will show a Play Store 404. Publish the app (even
an internal/closed test) or point playStore in config.js at wherever you share the APK.
