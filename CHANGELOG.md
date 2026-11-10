# Changelog

This fork collects the fixes from the community forks of [Leviidev/Henge](https://github.com/Leviidev/Henge)
into one build, with a few additions, aimed above all at iPad (tested hardware: iPad Pro M4).
Every change keeps its original author in the git history.

## 0.2.1 (103)

- **No Face ID prompt for iCloud when a Mac's settings open.** The page's *Move Out of Henge…* picker
  was SwiftUI's `.fileMover`, attached to the page all along, and iPadOS reached into iCloud Drive for
  it (asking for Face ID) every time the page opened. The system's document picker is now made only
  when that button is tapped.

## 0.2.1 (102)

- Settings > Display: *Sharp scaling* and *Strict GPU ordering* switches, the two display changes of
  this release, so a drawing problem can be traced to one of them (applies at the next Mac start;
  the log says which are on).
- The Mac's name field in its settings no longer offers AutoFill (iOS unlocks saved logins with Face ID).

## 0.2.1 (101)

Updates over 0.2.0 (100) in place: same bundle identifier (com.henge.app), and the Macs, their files and the settings are kept.

### Faster, and a cleaner picture
- **Loops run with one jump an iteration, not two (translator).** A loop's conditional branch back
  has to check whether its CPU was asked to stop (an interrupt, a TLB request); that check sat in the
  block's cold part, so every iteration jumped out to it and back. It now sits in the hot part, just
  before the branch (the existing `HV_HOIST_CHECK`, now on), and a chained branch goes straight to the
  loop's top. The check still runs every iteration, so a CPU stops as soon as before. Under qemu
  (arm64 Linux) the JIT's benchmark loops ran 2-5x faster (memory loop 4.5 -> 2.1 ms, tight loop
  12.5 -> 2.5 ms, jump table 6.9 -> 4.3 ms); qemu overstates taken branches, so a device gains less.
  `HV_HOIST_CHECK=0` in `henge-env.txt` turns it off.
- **`tools/qemu/run.sh`:** the engine's JIT, memory, MMU and benchmark tests on arm64 Linux under
  qemu, so translator changes can be checked against native execution without a Mac. Superblocks
  and grouped accesses were measured there too: no gain, so they stay off.
- **Engine statistics are off by default.** They were on in every build: each CPU counted into shared
  counters, every dispatcher cache miss walked the guest's page tables a second time to say what
  missed, and every 10 seconds CPU 0 walked the whole 2M-bucket block hash to print a log line, a
  regular hitch. Settings > Log > *Engine statistics* (or `HV_STATS=10` in `henge-env.txt`) turns
  them back on for a report.
- **No shared counters on the hot path.** Every guest CPU wrote the same cache lines on every
  dispatcher entry (the block count and a recent-blocks ring) and on every exception and return
  (an exception ring), so those lines moved between cores hundreds of thousands of times a second.
  The block count is now added in batches of 256 from each CPU's own state, and the debug rings are
  kept only with stats, `HV_JIT_POISON`, log level 2 or the new `HV_DEBUG_RINGS=1`.
- **A sharp picture at any Mac size (tuned for the iPad Pro 12.9).** The Mac's frame was drawn at its
  own size and Core Animation scaled it to the screen with plain bilinear sampling: a 1920×1440 "Fit"
  Mac on the 12.9-inch's 2732×2048 panel (1.42×) came out soft, and shrunk ones (a phone, an iPad
  window in Split View or Stage Manager) jagged and shimmering. The presenter now draws at the
  layer's own pixels and does the scaling itself: Catmull-Rom (a sharp cubic, nine bilinear taps)
  going up, a box filter going down. Up to the 12.9-inch panel's pixel count; zoomed in, the
  compositor takes it from there. `HV_PVG_SCALE=native` brings back the old way, `=down` only
  shrinks. The pointer is sampled smoothly whenever the frame is scaled.
- **iPad screen sizes:** a new *Fastest* size, 1440×1080 on a 4:3 iPad (44% fewer pixels than Fit,
  which macOS draws with the emulated CPUs), next to Retina, Fit, Performance (1600×1200) and 16:9.
  With the sharp upscale, Performance and Fastest stay readable on the 12.9-inch.
- **Lighter macOS goes further.** The command (Details > Lighter macOS) now also turns off
  scrolling, Finder, Quick Look, Mission Control and Launchpad animations, and, with the Mac's
  password once, the background work that competes with the app being opened: Spotlight indexing
  (mds_stores and mdworker reading every changed file), Time Machine, automatic update checks and
  downloads, App Store auto-updates and Power Nap. The script's comment promised the system part
  before; it never did it. Apps still open from Launchpad, the Dock and Finder. The undo command
  puts all of it back.
- **Quicker wake from idle is on by default.** Opening an app is thousands of messages between
  macOS's processes, each one CPU waking another, and waking a sleeping host thread takes far longer
  than the 50 µs an idle CPU now watches for work first. It costs some battery; Settings >
  Performance turns it off.
- **CPUs:** Mac settings say when a Mac has more CPUs than the chip has performance cores (4 on an
  M1): the rest run on efficiency cores and the others wait for them.
- The renderer reads `HV_PVG_TALLY` and the surface dump settings once, not per resource of every
  exec, and keeps one buffer for the guest's command buffers instead of a zeroed allocation each.
- **No more garbage in glass panels (Control Center, menus, notifications).** The guest's GPU work
  reaches Metal as many objects over the same memory (views of a surface in other formats, the
  render target and the texture a later pass samples, heap textures that can't be hazard-tracked
  on iOS), and Metal orders work only by object: a blur could read the backdrop while the pass
  drawing it was still running, and the screen could be shown while the panels drawn last over
  everything were still being drawn. Each encoder of the replay now waits for the one before it
  (two fences in turn), and the presenter waits on an event for the work of the frame it shows.
  `HV_PVG_ORDER=0` turns both off.
- A render pass whose store action the guest left Unknown (to set later in the pass, which isn't
  replayed) now stores its pixels instead of Metal discarding them.
- **iPhone screen sizes:** a Mac on iPhone was always 1920×1080. Mac settings now offer 900p
  (1600×900, 30% fewer pixels) and 720p (1280×720, 56% fewer). Everything macOS draws is drawn by
  the emulated CPUs and replayed on the GPU, so fewer pixels is faster everywhere.
- The session no longer resets its screen layer's colour space every second (SwiftUI's update ran
  with each status refresh), and copies the log only while Details is open.

### The screen is a Magic Trackpad 2
- The session's trackpad is no longer a relative mouse: the engine presents it to the Mac as
  a Magic Trackpad 2 (Apple's vendor multitouch format) on the xHCI USB bus, so the guest's
  own multitouch engine does the pointing and gestures: two-finger scroll, three-finger
  swipes for Spaces, Mission Control and App Exposé, two-finger taps for right-click, and so
  on. Settings > Trackpad picks the input mode: the touchscreen itself, or the volume buttons.
- **Touchscreen mode**: a quick tap is a left click, a quick two-finger tap is a right click,
  and touching then holding presses the button down so moving drags.
- **Volume-button mode** (iPhone): up is left click, down is right click (or swap them), and
  the surface only points and gestures. Settings offers three ways to read the buttons:
  *delay hold* (wait to detect a hold, so the click lags), *tap then drag* (click at once,
  then press down if still held), and *camera intercept* (true press/release via the camera;
  it always runs a frame stream, which the capture interaction needs, so the camera stays on).
- The session controls are now shown with a four-finger tap, leaving three fingers free for
  the Mac's own gestures.
- `devices/xhci.c` generalises the xHCI host to two USB devices (the keyboard and the
  trackpad). The report format follows the Linux kernel's `hid-magicmouse` MT2 support and
  VoodooInput's Magic Trackpad II emulation.

## 0.2.0 (100)

Based on upstream `main` at b744a78.

### Display colour
- macOS no longer looks pale: the half-float display surface is shown as WindowServer wrote it
  instead of being sRGB-encoded a second time. Colour probe for diagnosis (`HV_COLOR_PROBE`).
  — [hungbenjamin402](https://github.com/hungbenjamin402/Henge)
- Colour matching for the iPad's P3 panel (the Mac's frames are tagged sRGB), with live
  *Color matching*, *Linear color conversion* and *Brightness* controls in the session's Details.
  — [sonnx0868](https://github.com/sonnx0868/Henge)

### iPad, Magic Keyboard and trackpad
- Magic Keyboard scrolling calibrated, smoother input, and the device's thermal state in Details.
- Smaller, sharper pointer on iPad, with a size and a sharp-edges setting.
- Video planes copied through the IOSurface's real layout.
  — all three: [sonnx0868](https://github.com/sonnx0868/Henge)
- iPadOS's own hide-keyboard key ends typing, so the Mac takes the full screen again.
  — [gavinnolan](https://github.com/gavinnolan/Henge)
- Screen modes for a Mac on iPad: *Retina* (every pixel of the panel, at 2x), *Performance*
  (about 30% fewer pixels), *Fit this iPad* and *16:9*. Retina is opt-in: it costs a lot of
  emulated GPU work.
  — Retina from [AdamLovattDevOps](https://github.com/AdamLovattDevOps/Henge), Performance from sonnx0868
- 120 Hz ProMotion support, 4 GB default memory on 8 GB iPads, sampling profiler and GPU
  trace/shader dump tools. — [AdamLovattDevOps](https://github.com/AdamLovattDevOps/Henge)

### External display
- A Mac on an external display before iOS 27 too (iOS 17–26), the picture coming back to the
  device when the monitor is unplugged, and unplugging one display no longer freezes the others.
  — [hungbenjamin402](https://github.com/hungbenjamin402/Henge)

### JIT
- At launch, LocalDevVPN is connected first when it is off.
  — [braedonsaunders](https://github.com/braedonsaunders/Henge) (upstream PR #3)
- JIT on cellular: explains the failure and retries instead of blaming LocalDevVPN.
- Personal (free) teams can sign the app: `HENGE_ENTITLEMENTS`.
  — both: [hungbenjamin402](https://github.com/hungbenjamin402/Henge)

### New in this fork
- **Performance settings** (Settings → Performance), applied each time a Mac starts:
  - *Mac refresh rate*: 60 Hz by default. Every frame is emulated and replayed, so 120 Hz
    halves the CPU left to apps; 120 Hz stays available.
  - *Faster disk writes* (on): `F_BARRIERFSYNC` instead of a full `fsync`.
  - *Quicker wake from idle* (off): an idle CPU watches for work for 50 µs before sleeping.
  - *Superblocks (experimental)* (off): translated code runs on past conditional branches.
  - `Documents/henge-env.txt` still overrides everything.
- **Hide the session controls**: a button left of Keyboard hides the bar over the Mac; a
  four-finger tap brings it back (a hint says so the first three times). iPadOS's own
  three-finger undo/copy/paste bar is turned off inside the session so it doesn't interfere.
- Merges kept the Xcode 27 build: the built-in StikJIT helper and the Liquid Glass icon stay
  (the m4 fork's Xcode 16 changes, which remove them, are left out).
- Display name back to *Henge*; version 0.2.0 (100) so sideloading stores treat it as an update.

### Not included
- `HV_GROUPS` (grouped memory accesses): upstream measured it no faster and it fills the JIT
  region sooner.

## Building

As upstream (see README): Xcode 27, `xcodegen`, `meson`, `rustup` with `aarch64-apple-ios`,
and a built [Husk](https://github.com/Leviidev/Husk) at `~/Documents/Coding/Husk`. Only Husk's
`build_ios.sh libffi glib libslirp` and `build_rppairing_ios.sh` are needed for Henge.
