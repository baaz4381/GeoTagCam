# GeoStamp Cam (iOS, SwiftUI)

A camera app that burns a location stamp into every photo and video: map, address, coordinates, date and time,
altitude, compass, weather, QR code, your note, project name, hashtags and your logo. It also writes GPS into the
photo's EXIF metadata and keeps a tamper-check fingerprint of every capture.

This is original code, inspired by the feature list of GPS Map Camera-style apps. It uses no branding, assets or
code from any existing app.

## Fastest way to test on an iPhone

No Mac? Read **SIDELOADLY_GUIDE.md**. It builds the .ipa on GitHub for free and installs it with Sideloadly,
with a 16-step test checklist.

## Build with Xcode (needs a Mac)

Xcode 15.2 or later, and an iPhone (the simulator has no real camera).

**Option A: XcodeGen (easiest)**
1. `brew install xcodegen`
2. In the folder containing `project.yml`, run `xcodegen`
3. Open `GeoStampCam.xcodeproj`

**Option B: Manual**
1. Xcode > New Project > iOS App, name `GeoStampCam`, SwiftUI, Swift.
2. Delete the generated `ContentView.swift` and `GeoStampCamApp.swift`.
3. Drag the inner `GeoStampCam/` folder into the project (tick "Copy items if needed").
4. Target > Info: add `Privacy - Camera Usage Description`, `Privacy - Microphone Usage Description`,
   `Privacy - Location When In Use Usage Description`, `Privacy - Photo Library Additions Usage Description`
   (wording is in `project.yml`). Also add `Application supports iTunes file sharing` = YES.
5. Set the iOS Deployment Target to 16.0.

Then: choose your Team under Signing & Capabilities, change the bundle identifier, plug in the iPhone, Run.
On the phone, enable Developer Mode (Settings > Privacy & Security).

## Features

| Area | What you get |
|---|---|
| Photo | 0.5x ultra-wide, 1x/2x/3x/5x, pinch zoom, tap to focus, flash, timer 3s/10s, grid, front camera with mirror option, 4:3 / 1:1 / 16:9, volume-button shutter (iOS 17.2+), screen stays awake |
| Video | Stamped video with live clock (to the second) and live position, 720p or 1080p, sound, torch, timer. Recorded upright |
| Stamp templates | Classic, Advanced, Compact, Compass |
| Stamp fields | Map (standard, satellite, hybrid), address, country flag, lat/long (decimal or DMS), date formats with time zone, altitude, accuracy, compass, magnetic field, temperature, humidity, wind, pressure, project, note, hashtags, logo, QR code to the location, running photo number |
| Stamp look | Top or bottom, size, opacity, highlight colour, metric or imperial |
| Quick note | Pencil button on the camera: switch project, note and hashtags without opening Settings |
| Projects | Saved project list, tap to select, gallery can be filtered by project |
| Before / After | "Tag" button; PDF reports pair them side by side |
| Import | Gallery > + stamps photos you already have, using their original GPS and time. If a photo has no GPS the stamp says "Location unavailable" and is marked IMPORTED |
| Gallery | Photos and videos, filter (type, tag, project), search (address, note, project), multi-select, share, delete, video playback, copy coordinates, open in Maps, re-save to Photos |
| Export | PDF report, CSV spreadsheet, KML for Google Earth, share original files |
| Trust | Burned-in stamp, GPS in EXIF, SHA-256 per capture with a Verify button, network-time check against a wrong phone clock, "Simulated location" warning |
| Files app | Everything is also visible in Files > On My iPhone > GeoStamp Cam, so you can copy it to iCloud Drive, Google Drive, a USB drive and so on |
| Privacy | No account, no ads, no analytics. Microphone is only used in Video mode, so photos never pause your music |

## Things to know

- **Not compiled in the build environment.** Expect a small number of compiler fixes on the first build. Send me the
  `error:` lines and I will fix them. The least certain spots are the volume-button code in
  `Views/Components.swift` (if it errors, delete the `installHardwareButton` body) and the layout sizes in
  `Views/CameraScreen.swift`.
- **Tamper-resistance is limited.** iOS reports when a location is software-simulated and the stamp warns about it,
  but a determined person with a jailbroken phone can still fake data. The SHA-256 check only proves the file was
  not edited after capture. For legal or audit use, also keep your own server-side record.
- **Imported photos are not proof of when or where they were taken.** They are labelled IMPORTED for that reason.
- **Weather** comes from Open-Meteo (free, no key, non-commercial use). For a commercial app use their paid plan or
  Apple WeatherKit.
- **Address and map** use Apple's geocoder and Maps snapshots and need internet. Offline, the stamp shows
  coordinates only.
- **Altitude** is GPS altitude, not barometric.
- **Video** is always recorded in portrait. Change quality before switching to Video mode.
- **Not included yet:** other languages, Google Drive sync (use the Files app), landscape video, custom stamp
  dragging. Ask and I will add them.
- **App Store:** needs a paid Apple Developer account, an app icon, a privacy policy URL and the privacy label
  (location, photos, microphone).

## File map

- `Models/` settings and capture data
- `Services/` location, weather, map, clock check, camera, video recorder, photo import
- `Rendering/` stamp text builder, image renderer, QR and compass drawing, EXIF writer
- `Storage/` gallery store, hashing, save to Photos
- `Reports/` PDF, CSV and KML
- `ViewModels/CameraViewModel.swift` ties it together
- `Views/` camera, gallery, photo detail, settings, quick note
- `.github/workflows/build-ipa.yml` cloud build for Sideloadly
