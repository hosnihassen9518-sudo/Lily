# Phone media and external Bluetooth output

User requests server catalog selection, files from the phone, and output from other
phone apps. User selected conventional Bluetooth audio through additional receiver
hardware rather than Android Wi-Fi audio capture.

## Current repair
Add Choose music on the audio-device page, scoped to that device. Empty server
catalogs have a readable explanation instead of a blank list. App 0.10.3+12.

## Approved phone-file design
Choose MP3 on phone using the existing file_picker dependency. Upload the selected
file to the configured Lily server as a private owner-scoped track (20MiB ceiling),
then reuse existing automatic local storage / Wi-Fi streaming fallback and explicit
stream mode. Server catalog and My files appear separately. Private tracks are never
listed/downloadable/playable by another account. Add nullable owner_id to Music with
a migration; null denotes the existing shared catalog. Limit upload reads and clean
up files on failure. No ESP32 firmware update is required for this path.

Alternatives: direct phone-to-board upload needs address discovery, authorization,
and another firmware endpoint; phone-hosted streaming needs foreground/background
network hosting. Server relay is recommended for compatibility with the current
authenticated catalog command and storage safeguards. It requires server upload
and storage, so user must confirm that tradeoff.

## External Bluetooth output (hardware details pending)
ESP32-S3 has no Classic Bluetooth A2DP. An additional receiver must provide compatible
I2S output or its own suitable amplifier path; analog-only receiver output cannot
feed MAX98357A directly. Determine exact module before selecting pins, bus switching,
or firmware. Never join the outputs of two I2S masters directly. The app can expose
an explicitly labelled external-receiver setup action that opens Android Bluetooth
settings; show the hardware prerequisite. Standard phone output selection then routes
other apps to the paired receiver, rather than capturing their audio in Lily.

User approved private server uploads and deferred Bluetooth audio entirely. Do not
add Bluetooth controls or change firmware in this iteration. Receiver details and
physical switching are future work. Implement only private phone MP3s plus catalog.
