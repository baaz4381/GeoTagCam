# Test GeoStamp Cam on your iPhone with Sideloadly (no Mac needed)

Sideloadly installs an **.ipa file**. An .ipa can only be built by Apple's tools (Xcode), which run on a Mac.
Step 1 gets you an .ipa for free using a GitHub Mac in the cloud. Step 2 installs it with Sideloadly.

If you own a Mac, skip Step 1 and follow the Xcode steps in README.md instead.

---

## Step 1. Get the .ipa (about 15 minutes, once)

1. Create a free account at github.com.
2. Click **+ > New repository**. Name it `geostampcam`. Choose **Public** (unlimited free build minutes) or
   Private (free allowance is enough for several builds). Click Create.
3. On the new repository page click **uploading an existing file**.
4. Unzip `GeoStampCam.zip`. Open the `GeoStampCam` folder. Select **everything inside it** (`project.yml`,
   `README.md`, the `GeoStampCam` folder, the `Config` folder and the `.github` folder) and drag it into the browser.
   `project.yml` must end up at the top level of the repository, not inside another folder.
   - If your computer hides the `.github` folder: on the repository page choose **Add file > Create new file**, type
     the name `.github/workflows/build-ipa.yml`, and paste in the contents of that file.
5. Click **Commit changes**.
6. Open the **Actions** tab. If asked, click "I understand my workflows, go ahead and enable them".
7. Click **Build IPA** in the left list, then **Run workflow > Run workflow**.
8. Wait 5 to 10 minutes until the run shows a green tick.
9. Open the finished run, scroll to **Artifacts**, download **GeoStampCam-ipa**, and unzip it. Inside is
   `GeoStampCam.ipa`.

**If the run fails (red cross):** open the run, download the **build-log** artifact (or open the "Build" step),
find the lines containing `error:` and send them to me. The code was written without a compiler, so a few small
fixes on the first build are normal.

---

## Step 2. Install with Sideloadly

### On the computer
- **Windows:** install iTunes and iCloud from **apple.com/itunes** (the downloadable versions, not the Microsoft
  Store versions), then install Sideloadly from **sideloadly.io**.
- **Mac:** just install Sideloadly.

### Install the app
1. Connect the iPhone with a cable. Unlock it and tap **Trust** on the phone.
2. Open Sideloadly. Your iPhone appears at the top.
3. Drag `GeoStampCam.ipa` onto Sideloadly.
4. Type your **Apple ID** email. A spare Apple ID is wise. A free one is enough.
5. Click **Start**. Enter your Apple ID password. Enter the two-factor code if asked.
   If Sideloadly offers an app-specific password option, use it.
6. Wait for "Done".

### On the iPhone
1. **Settings > General > VPN & Device Management** > tap your Apple ID under "Developer App" > **Trust**.
2. **iOS 16 and later:** **Settings > Privacy & Security > Developer Mode** > turn **On** > restart > confirm.
   This switch only appears after an app has been sideloaded.
3. Open **GeoStamp Cam**. Allow:
   - Camera
   - Location: **While Using the App**, with **Precise Location** on
   - Photos (add photos only)
   - Microphone (asked the first time you switch to Video)

### Free Apple ID limits
- The app **expires after 7 days**. Run Sideloadly again with the same .ipa to renew it. Your photos and settings
  stay.
- A free account can have only **3 sideloaded apps** active at once.
- A paid Apple Developer account makes it last a year.

---

## Test checklist

Go **outside or near a window** first so GPS can get a fix.

| # | Test | Expected |
|---|---|---|
| 1 | Open the Camera tab | Chip top-left turns green ("GPS ±10 m" or better) within a minute |
| 2 | Look at the stamp | Address, coordinates, date and time appear and the map fills in |
| 3 | Take a photo | "Saved to Photos and gallery". Thumbnail appears bottom-left |
| 4 | Photos app > open the photo > swipe up | A map pin shows where it was taken |
| 5 | Settings: change Template, toggle fields | Live preview changes. New photos match |
| 6 | Tap **Tag** to Before, shoot, then After, shoot | Gallery shows yellow tags. PDF pairs them |
| 7 | Switch to **VIDEO**, record 10 seconds | Timer runs. Saved video shows the stamp with the clock moving |
| 8 | Gallery > **+** > pick an old photo | Stamped copy appears marked IMPORTED. If it had GPS, the stamp shows it |
| 9 | Gallery > Select > a few items > PDF, Data (CSV or KML), Share | Files open in the share sheet |
| 10 | Photo detail > **Verify** | Green "File is unchanged" |
| 11 | Settings > QR code on, take a photo, scan the QR with another phone | Opens a map at that spot |
| 12 | Settings > Running photo number on | Stamp shows Photo No. 1, 2, 3 |
| 13 | Camera: pinch, tap to focus, 0.5x chip, timer, flash | Each works |
| 14 | Press a volume button on the camera screen | Takes a photo (iOS 17.2 or later) |
| 15 | Play music, open the camera, take a photo | Music keeps playing |
| 16 | Turn on Airplane Mode, take a photo | Photo still saves. Stamp shows coordinates, no address or weather |

Tell me which numbers fail and what you see, and I will fix them.
