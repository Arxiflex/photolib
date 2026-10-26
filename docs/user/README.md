# User guide

Photolib is pre-alpha and there is nothing to install yet, so this guide has little content yet. It grows with the
features: a change that alters what a user sees updates this guide in the same pull request. Until then, the
feature catalogue and the client app design describe the planned behaviour.

## Android

* Photolib shows the photos and videos of the phone, SD cards included; those of a removed card return with it.
* A gallery needs access to all of them: with access to selected photos only, or none, the library says so and its
  *Allow access* button asks again, or opens Photolib's settings once Android stopped asking.
* Settings › Library › Device folders lists every folder of the phone and its cards with a switch, and whether the
  library shows all folders but the excluded (the default, which leaves out app data, caches and the album art of
  music folders) or only the chosen ones. A new folder asks once to be kept or excluded. A long press then *Exclude
  this folder* in the library, the photo's info or search's folder list excludes a folder in one tap; the library's
  view options show the excluded folders for 5 minutes. Photolib never writes or reads `.nomedia` files.

## Computers

* On Windows, macOS and Linux the library is made of folders: *Add folder*, in the empty library or in Settings, adds
  one, which Photolib scans and then watches. Settings lists each folder as scanning (with the items found so far),
  online or offline (its drive is away; its items stay), with its number of items.
* Removing a folder in Settings removes its photos and videos from the library and never touches the files.
* Linux keeps Photolib's keys in the keyring (Secret Service). Where none runs, Photolib asks you once to choose a
  passphrase of at least 10 characters, then for it at every start; it stays the way in after a keyring appears.
* The [release notes](release-notes.md) list known issues, such as a crash on macOS when the app comes back to the
  front.

## Text in photos

* Photolib reads the words in your photos (signs, tickets, screenshots, in Latin, Cyrillic, Chinese and Japanese
  script) and finds the photos by them. With a server, the server reads them (an administrator installs the OCR
  models, see [models](../admin/models.md#reading-text-in-photos)); on Windows, macOS and Linux, *Settings › Read text
  in photos* does it on the computer after a download of about 190 MB, and works without a server. On Android (Google
  Play build) and iPhone the same switch uses the phone's own text recognition, with nothing to download; it reads
  the photos you take while the app is open (Cyrillic only with a server, as Android's recognition does not read it).
* Type words of the text in *Search*: a photo is found when they are in its name or in the text it holds, in any case.
* *Copy text* (in the viewer's bar or its ⋮ menu) shows the text of a photo of your server and copies it. The text is
  what the picture says, whoever made it: Photolib shows it as plain text and never runs it.

## The store on this device

* Photolib encrypts what it keeps on the device under a key the system's keystore holds (on Linux the keyring, or your
  passphrase, above); while a keyring that holds it does not answer, the library names gnome-keyring, KWallet and
  KeePassXC.
* While changes exist only on this device, the library offers a *recovery code*: 24 words to write down. *Later* asks
  again in 30 days; *Settings › Recovery code* makes one at any time, replacing the last.
* Should the keystore lose Photolib's key (a reset phone, a new keyring password), the library asks for the code,
  which opens the store as it was; without a code, the store starts afresh: libraries sync again and thumbnails come
  back, and what existed only on this device is lost, as the library says.

## Editing

* In the viewer, *Edit* (`e` on a computer) crops, rotates, flips and auto-enhances a JPEG photo on Android and
  computers. *Save copy* saves the edit as a new photo beside the original, `<name>_edit.jpg`, and shows it (where
  Photolib may not write, as in a Mac's folders after a restart, it asks where); the original never changes. Date, place
  and camera details stay with the copy; a turn, and a crop of most camera photos, keep its quality exactly (a crop may
  then take up to 15 more pixels at its top or left).

## Your server

* *Settings › Server › Add a server* connects Photolib to your server: its addresses, one a line (at home, on the
  internet, through a VPN; the fastest that answers is used), and if your server needs them a private CA certificate,
  a client certificate, an HTTP proxy or headers. A server with a self-signed certificate shows its fingerprint: trust
  it only if it is your server's.
* Sign in with your email or sign-in name and password; the password never leaves the device. An account with a
  second factor then asks for a code from your authenticator app, a recovery code or, on a computer, a passkey in your
  browser. A new server is set up with *Set up a new server* and the setup token from its log; *Set a password* takes a
  password setup token from your administrator. The session stays across restarts, renewed while you use the app,
  until you sign out or the server ends it; a server that does not answer keeps you signed in.
* *Your devices* on the server's page lists the devices signed in to your account and signs one out, this one too.
  *Second factors* there lists your passkeys, authenticator app and recovery codes; on a computer *Add a passkey*
  creates one in your browser. A change asks for your password or a code first unless you signed in moments ago.
  Administrators also find *Server administration* in Settings.
* Signed in, Photolib syncs with the server, again whenever it comes back, and once you turn
  [backup](#backing-up-this-device) on, backs the device up into your library there. The library shows your server's
  photos beside the device's, one tile per photo. A crossed cloud marks a photo *Not backed up*, a cloud one *Cloud
  only* (only on the server); a backed-up photo has no badge. *View options* shows one of these at a time, or hides the
  badges. Signing out removes the server's photos from the device; the next sign-in brings them back.
* Add more servers, or more accounts on one, the same way: each keeps a library of its own on this device, and the
  app bar's *Switch account* changes between them in one tap. Removing one signs it out and forgets what it synced.

## Viewing

* In the viewer a tap on the left or right edge shows the previous or next item, and a double tap held and dragged
  zooms with one finger (down in, up out). On a video, swiping up or down on the left third sets the brightness and on
  the right third the volume. *Settings › Viewing* turns each of these off, and turns on full brightness while
  viewing, turning a phone to each item's orientation, looping videos, going on to the next item when one ends,
  resuming videos where they were left, animated GIFs in the grid (GIFs have a badge) and playing videos with sound
  over other audio, which they pause otherwise (a silent video never does). It also chooses what shows behind
  transparent images and which buttons the viewer's bar holds, in order.
* A selection has no limit, and *Select all* is in every grid. While selecting, a tap anywhere on a photo selects or
  deselects it, and a long press shows it larger until you lift your finger.
* The place in the library, the selection, the view options, the search and the item open in the viewer stay as they
  were when the screen turns, you switch tabs or close the viewer, and after a restart if the library has as many
  items. Downloaded and shared files are dated when they were taken (in a browser, only those in a zip).

## Folders and albums

* *Collections › Folders* lists the folders that hold photos and videos, each with its count, its newest item and, on
  a phone, whether it is on the SD card; music, album art and app caches stay hidden until *Show excluded folders*.
  Drag folders into your order and pin the ones you want on top; new files never reorder them.
* A folder or album remembers its sort (name with numbers in order, date taken, date modified, size, random or type,
  ascending or descending) and its grid or list of names, sizes and dates; the viewer pages in that order.
* *Collections › Albums* holds your albums inside folders as deep as you like. *Add to album* fills an album from a
  folder or a selection, and *Use as cover* picks its cover. They work without a server.
* On computers a folder's selection can be renamed with a pattern (`{name}`, `{n}` or `{nnn}`, `{yyyy}`, `{MM}`, `{dd}`,
  `{HH}`, `{mm}`, `{ss}`, find and replace), with a preview of every name and an undo, and moved or copied: the dialog
  starts in the folder, offers recent targets and *New folder*, shows each file's progress, and can be undone. Files
  keep their bytes and dates.
* *Settings* choose the start screen (timeline, folders and albums, or favourites) and the tab folders and albums
  open on.

## Favourites, hiding and the trash

* A selection's heart, in the library, a folder or an album, marks it favourite (or takes the mark off when all are);
  favourites carry a heart in every grid and the *Favourites* filter of Search finds them. In the viewer `f` does the
  same.
* *Hide* takes items out of every view, *Archive* out of the timeline only. The eye in the library's toolbar shows
  both for 5 minutes, until the app goes to the background; meanwhile *Unhide* and *Unarchive* take them back. Photolib
  keeps this state itself, never in `.nomedia` files, and finds it again for an item moved or renamed outside Photolib.
* *Move to trash* (`Delete` in the viewer) offers *Undo*. Signed out it asks nothing; signed in it first says how many
  of the items, and how large, are on this device and backed up, only on this device, or only in your library, then
  offers *Move to trash*, each copy into its own trash (the device's and your library's), or for backed-up items
  *Remove from this device*, which your library keeps. A device's copies go to the system's trash: Android's, which
  Files lists; on iOS Recently Deleted in Photos, where Photos asks first and only Photos restores, so there is no
  *Undo*; on computers the trash or Recycle Bin of the file manager. Browsers, and network drives on Windows, keep
  items in Photolib's own trash, on disk until deleted for good. A computer folder's *Delete folder* moves its photos
  and videos there too, from this device only, after asking.
* *Trash*, in the library's toolbar, shows each item's time left and restores it where it was. *Delete forever* exists
  only there and asks once (unless Android or Photos asks themselves). Photolib keeps what it holds there for 60 days.
* Signed in, an album of your library has a *Hide* menu in its toolbar: *Hide from timeline* takes its photos out of
  the library's timeline on every device you use, *Hide from memories* out of memories. They stay in the album and in
  Search; the checks show what is hidden.
* *Empty trash* also empties your library's trash on the server, which deletes the files for good. It asks once with
  the number of items; when the server holds back a large trash (over 1,000 items or 5 % of your library) it asks again
  with the server's own number, and deletes nothing until you confirm that. Items in your library's trash that you do
  not empty go for good after the days your administrator set (30 unless changed). Items in a library the server
  only reads from a folder (an external library) stay in the trash. Albums you made on this device while signed out go
  to your account with their ids and photos once the photos are backed up.

## Search

* Search finds photos and videos by words in their file and folder names (`*` and `?` are wildcards) and by filters:
  dates, photos or videos, favourites, panoramas, motion photos, screenshots, a folder with its subfolders and a camera.
  Every filter set must hold. Results select as in the library.

## Map

* *Map* (in Collections) shows every photo and video that has a place, grouped by how close they are; tap a group to
  zoom into it, a single photo to open it. The slider underneath limits the map to a time range, the loop button lets
  you draw around photos to select only those (the clear button removes the loop), the haze button shows where most
  were taken, the timeline button draws a line through the places of photos taken within hours of each other (a
  trip), and the button under the map shows the photos of what you see in a grid, which select as in the library.
  *Search this area* opens Search limited to the area (a loop counts as the box around it). The route button adds a GPX
  file: its tracks are drawn in a colour for what they were (walking, running, hiking, cycling, driving).
* Everything runs on this device. The map's background is asked from OpenStreetMap's server only after you tap *Show
  the background*, which then sees which area you look at; without it the groups show on a plain background.

## Faces and people

Photolib finds the faces in your photos and videos only if you agree: *Settings › Faces and people* shows what is
found and kept (where a face is and a list of numbers that describes it, which can count as biometric data), where
(this device and, when you are signed in, your own server, never a service of ours) and that it is optional. Agreeing
downloads two small models; withdrawing deletes every face, description and person found for you, on the device and on
your server. While the photo's info is open, its faces are outlined on it. A copy you make with the editor shows the
original's faces moved with the edit, at once.

## Slideshow

* *Slideshow* plays full screen what the viewer shows from the item shown (`s`), what is selected, or search results:
  each item for the seconds set in its options, fading into the next (at once under reduce motion), in order or
  shuffled, each once, and once or repeating. A video plays to its end, a motion photo its video once, an animated GIF,
  WebP or PNG its frames. Space pauses, the arrow keys step and Esc ends it; the screen stays on meanwhile.

## Browsers

The web app's [supported browsers](browsers.md) come in three tiers, with known limitations.

* In Chrome and Edge on a computer, *Add folder* opens a folder on this computer as the library, scanned when the page
  opens or is shown again. When the browser asks again, *Allow access* on the folder in Settings lets it read the
  folder, on every visit if you choose; until then the folder is offline. Other browsers say they cannot keep folders.

## Keyboard and accessibility

* On a computer, `?` lists every keyboard shortcut and Ctrl+K (Cmd+K on a Mac) searches the commands; `/` opens
  Search and Ctrl+, (Cmd+,) the settings. In the library the arrow keys move a ringed focus through the photos, Space
  selects the one in focus, Shift with an arrow selects on, and Enter opens it; in the viewer `t` shows the filmstrip.
* The app follows the system's reduce motion and high contrast settings.
* *Settings › Language* shows the app in the device's language, the default, or in any of its 21 languages, each
  listed in its own name; dates, numbers and sizes follow it at once. On Android 13+, iOS and macOS the system's
  per-app language setting lists the same languages and sets the device's language for Photolib alone.

## Reporting a bug

Settings › *Diagnostics* shows the app's recent log, filtered by level and source, and copies what it shows. *Export
diagnostic bundle* saves a zip to attach to a bug report: the log, the versions of the app, system and browser, the
settings and how many items of each kind the library holds. Released versions keep no file or folder names in their
log or bundle, keep the log encrypted on the device, and show Diagnostics once *Show diagnostics* is on in Settings.
Nothing leaves the device unless you save or share the bundle.

## Backing up this device

Once the app is signed in to a server, Settings › *Backup* › *Back up this device* sends the device's photos and
videos there, into your library (made at the first backup), while the app runs: at start, every 15 minutes and on
*Back up now*. On phones, background backup comes with a later version.

* Choose the folders, photos or videos, and a date before which nothing is sent. A folder that appears later is asked
  about once on the home screen.
* On metered networks (mobile data, a phone's hotspot or tethering) photos up to 50 MB go and videos wait for Wi-Fi;
  both can change. Backup also waits while roaming, on a low battery off the charger, or until the device charges if
  you choose.
* *Not backed up* lists why each item waits, with when a failed one is tried again. The home screen shows the last
  complete backup and what waits, warns when backup has not completed for a day (or the hours you choose), and says
  when the server has signed the device out until you sign in again. While the server is out of reach it says when
  the device last reached it.
* Backup never stops for a sign-in: the app renews the device's session before it expires. Quitting or killing the app
  loses nothing: the next backup resumes where it stopped, and nothing is sent twice.

## Uploading from the command line

`photolib upload` sends photos and videos from folders, memory cards or a NAS into a library, such as your
[library *Photos*](../admin/users.md#a-library-to-back-up-into). It signs in with an
[API key](../admin/users.md#api-keys) with the `contribute` scope in `PHOTOLIB_TOKEN`. A file takes at least two
requests, so give a key for a large library a rate above the default 600 a minute; beyond it, uploads wait, up to a
minute at a time.

```sh
export PHOTOLIB_SERVER=https://photos.example.org PHOTOLIB_LIBRARY=<library id> PHOTOLIB_TOKEN=<API key>
photolib upload --dry-run /media/card/DCIM   # list what would be sent
photolib upload /media/card/DCIM ~/Pictures  # send it
```

* It sends the files you name and, in folders, the photos and videos the app shows, without what `.photolibignore`
  files exclude or NAS thumbnails and trash folders.
* Run it again whenever you like: an interrupted run goes on where it stopped, files sent before are skipped without
  being read, and identical files are sent once. Its journal is `~/.local/state/photolib/<library id>.jsonl`.
* A file counts as uploaded only once the server has checked its BLAKE3 hash and stored it. `--json` prints one JSON
  object a line, each file with its hash, so a script can clear a card once every file is `uploaded` or `duplicate`.
* It exits with status 1 when a file failed, or when the server refused the key, the library or a full quota, or could
  not be reached: run it again to go on.

## Keeping photos offline

* *Settings › Storage* says what this device keeps of your server's library, as one of four choices: *Catalogue
  only* (nothing; photos load when you open them), *Space saver* (previews of the whole library, newest first),
  *Selected albums offline* (only what you pin, the default) and *Everything* (the originals of the whole library).
  The *Storage budget* is the most space it may take; the bar shows what it uses now, to the byte. A browser keeps
  previews only, and erases them when you sign out.
* The pin in an album's bar, in the results of a search and in the viewer (*Keep on this device*, with the size it
  adds) keeps that album, search or photo available with no network. A pinned album says how far it is: *Downloading*,
  *Will download when online* (nothing is lost while there is no signal), *Available offline* or *Does not fit the
  budget* with how much more it needs. A small pin marks the photos kept on this device.
* Pinned photos and videos open, scroll and play in airplane mode. *Keep originals too* on a pin keeps the original
  files as well as the previews.
* Letting go of a pin, or *Remove offline copies*, frees exactly the space it showed. Copies are sealed on the device
  like the rest of its store, and a private library's stay encrypted: they are opened only to be shown.
