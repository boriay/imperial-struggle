# Signing and notarizing Imperial Struggle for macOS

Passwords, your Apple ID and certificates stay on your Mac only. None of them are ever written to project files.

## Step 1. Join the Apple Developer Program ($99 per year)
1. Turn on two-factor authentication for your Apple ID on the Mac (System Settings → your name → Sign-In & Security).
2. The fastest way: install the **Apple Developer** app from the App Store, sign in with your Apple ID and tap **Account → Enroll Now**. You can also enroll on the website: https://developer.apple.com/programs/enroll/
3. Type: **Individual / Sole Proprietor** (a private person; the game will show your name). An organization needs a D-U-N-S number, which takes longer.
4. Pay $99. Confirmation usually arrives within a few minutes to 48 hours as a "Welcome to the Apple Developer Program" email.
5. After confirmation open https://developer.apple.com/account → **Membership details** and write down your **Team ID** (10 characters, for example `AB12CD34EF`).

## Step 2. Developer ID Application certificate
Using Xcode (the easier way):
1. Install Xcode from the App Store (`xcode-select --install` is not enough: the certificate needs full Xcode).
2. Xcode → Settings → **Accounts** → "+" → Apple ID → sign in.
3. Select your team → **Manage Certificates…** → "+" → **Developer ID Application**.
4. Check in Terminal:
   ```
   security find-identity -v -p codesigning
   ```
   There should be a line `Developer ID Application: Your Name (TEAMID)`.

Only the account owner (Account Holder), that is you, can create a Developer ID certificate.

## Step 3. App-specific password for notarization
1. https://account.apple.com → **Sign-In and Security** → **App-Specific Passwords** → create one and name it `notarytool`.
2. Save it to the Keychain right away (the password is asked interactively):
   ```
   xcrun notarytool store-credentials imperial-notary --apple-id "your@apple.id" --team-id "YOUR_TEAM_ID"
   ```
   From then on the script uses the `imperial-notary` profile and the password is not needed anywhere else.

## Step 4. Sign and notarize the build
The `signing/` folder contains `sign_and_notarize.sh` and `entitlements.plist`. On the Mac:
```
cd path/to/imperial-struggle/signing
./sign_and_notarize.sh ../export/ImperialStruggle-macOS.zip
```
The script finds the certificate, signs with the hardened runtime, sends the app to Apple, waits for the answer, staples the ticket and creates `ImperialStruggle-macOS-signed.zip`.

If notarization is rejected, see why:
```
xcrun notarytool history --keychain-profile imperial-notary
xcrun notarytool log <submission-ID> --keychain-profile imperial-notary
```

## Step 5. Check
```
spctl --assess --type execute --verbose=4 "Imperial Struggle.app"
```
Expected: `accepted, source=Notarized Developer ID`. Final check: send the zip to another Mac (or download it through a browser), unpack it and double-click the app. There should be no Gatekeeper warning.

## Alternative: signing straight from Godot on a Mac
In Godot 4.5 on a Mac: Project → Export → macOS → **Code Signing: Xcode codesign**, Identity: `Developer ID Application`, enable Hardened Runtime; **Notarization: Xcode notarytool**, Apple ID + app-specific password + Team ID. Godot keeps these in `.godot/export_credentials.cfg`, and that file must never be shared. The script is the safer option: the secrets stay in the Keychain only.
