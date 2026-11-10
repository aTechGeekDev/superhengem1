import SwiftUI
import UIKit
import GameController

/// What this device is, for what the app says and suggests.
enum Device {
    static let isPad = UIDevice.current.userInterfaceIdiom == .pad
    static let name = isPad ? "iPad" : "iPhone"

    /// A Mac's screen that fills this device on its side: 1920 wide, as tall as the shape asks. iPads and
    /// squarer phones (iPhone Duo, about 1.46:1) would get bars above and below at 16:9. Phones wider
    /// than 16:9 come out at 1920×1080, as before.
    static var fittingScreen: (width: Int, height: Int) {
        let size = UIScreen.main.bounds.size
        let shape = max(size.width, size.height) / max(min(size.width, size.height), 1)
        return (1920, min(max(Int((1920 / shape / 8).rounded()) * 8, 1080), 1440))
    }

    /// Preserve the iPad's shape while reducing the virtual GPU's pixel work.
    static var performanceScreen: (width: Int, height: Int) {
        let fit = fittingScreen
        return (1600, Int((Double(fit.height) * 5 / 6 / 8).rounded()) * 8)
    }

    /// Fewer pixels still, in the iPad's shape: 1440×1080 on a 4:3 iPad (44% fewer than Fit). macOS draws every
    /// pixel with the emulated CPUs; the presenter scales it up to the panel with a sharp filter.
    static var fastestScreen: (width: Int, height: Int) {
        let fit = fittingScreen
        return (1440, Int((Double(fit.height) * 3 / 4 / 8).rounded()) * 8)
    }

    /// The chip's performance cores (4 on an M1). A guest CPU on an efficiency core runs at a fraction of the
    /// speed, and the others wait for it whenever they need it (TLB shootdowns, locks), so more guest CPUs than
    /// this is usually slower, not faster.
    static let performanceCores: Int = {
        var n: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &n, &size, nil, 0) == 0, n > 0 { return Int(n) }
        return max(ProcessInfo.processInfo.activeProcessorCount / 2, 1)
    }()

    /// The panel itself, on its side: every physical pixel, and its real size in mm so that macOS
    /// sees a Retina density and draws at 2x (looks like half the pixels, sharp as the iPad's own UI).
    /// Every iPad with an M chip is 264 ppi.
    static var retinaScreen: (width: Int, height: Int) {
        let n = UIScreen.main.nativeBounds.size
        return (Int(max(n.width, n.height)) / 8 * 8, Int(min(n.width, n.height)) / 8 * 8)
    }
    static var retinaMM: (width: Int, height: Int) {
        let s = retinaScreen
        return (Int((Double(s.width) / 264 * 25.4).rounded()), Int((Double(s.height) / 264 * 25.4).rounded()))
    }

    /// How much memory to suggest for a new Mac: what leaves this device room for iOS.
    static var suggestedRAMGB: Int {
        let mb = ProcessInfo.processInfo.physicalMemory >> 20
        // m4 fork: an 8 GB iPad (7.4 GB usable) thrashes and kills the Mac at 6 GB: 16 GB devices only.
        return mb >= 14_000 ? 8 : mb >= 10_000 ? 6 : 4
    }

    /// The choices for a Mac's memory, in GB.
    static let memoryChoices = 1...16

    /// What a choice risks on this device, if anything. An install always gets at least 2 GB (Installer.install).
    static func memoryNote(_ gb: Int) -> String? {
        if gb < 4 { return "macOS has little room under 4 GB, so it can be very slow." }
        if gb > suggestedRAMGB { return "More than \(suggestedRAMGB) GB is a lot for this \(name): iOS may close Henge when macOS gets busy." }
        return nil
    }

    /// The virtual CPU offers Armv8.5 instructions (core/sysreg.c), and macOS uses them. They run as
    /// they are, so the chip needs them too: A14, M1 and later, which is iPhone13,x and iPad13,x up.
    static let chipTooOld: Bool = {
        let model = HengeLog.deviceModel
        guard model.hasPrefix("iPhone") || model.hasPrefix("iPad"),
              let major = Int(model.drop { !$0.isNumber }.prefix { $0.isNumber }) else { return false }
        return major < 13
    }()

    static let chipTooOldText = "macOS won't run on this \(name). Henge needs an A14 or M1 chip or newer."
}

/// A keyboard attached to the device. iOS reports each key going down and coming up by its HID usage,
/// which is what the Mac's USB keyboard sends, so every key and modifier goes straight across.
enum HardwareKeys {
    private static var held: Set<UInt8> = []
    private static var lastKey: CFTimeInterval = 0

    /// With the on-screen keyboard's view holding the keyboard, iOS may also offer a hardware key as
    /// text, and again as it repeats. The Mac has the key already, and repeats it itself.
    static var keyJustPressed: Bool {
        held.contains { $0 < 0xe0 } || CACurrentMediaTime() - lastKey < 0.1
    }

    /// Sends the presses that are keys, and returns the rest.
    static func send(_ presses: Set<UIPress>, down: Bool) -> Set<UIPress> {
        var rest = Set<UIPress>()
        // A chord can arrive in one unordered Set. Press modifiers first and
        // release them last so the guest sees the intended shortcut.
        let ordered = presses.sorted { a, b in
            let aCode = a.key?.keyCode.rawValue ?? 0
            let bCode = b.key?.keyCode.rawValue ?? 0
            let aModifier = (0xe0...0xe7).contains(aCode)
            let bModifier = (0xe0...0xe7).contains(bCode)
            if aModifier != bModifier { return down ? aModifier : !aModifier }
            return aCode < bCode
        }
        for press in ordered {
            guard let raw = press.key?.keyCode.rawValue, raw >= 0x04, raw <= 0xe7 else {
                rest.insert(press)
                continue
            }
            let usage = UInt8(raw)
            henge_vm_key_hid(usage, down ? 1 : 0)
            if usage < 0xe0 { lastKey = CACurrentMediaTime() }
            if down {
                held.insert(usage)
            } else {
                held.remove(usage)
                if usage < 0xe0 { StickyKeys.shared.releaseAll() } // one key after a tap on ⌃, ⌥ or ⌘
            }
        }
        return rest
    }

    /// iPadOS can keep a key's release when it takes over, as it does for ⌘-Tab: the Mac must not
    /// go on thinking the key is down.
    static func releaseAll() {
        for usage in held { henge_vm_key_hid(usage, 0) }
        held.removeAll()
    }
}

/// Asks iPadOS to hand the pointer over, so a trackpad or mouse drives only the Mac's pointer. It does
/// that only for an app filling the screen. SwiftUI has no way to ask, so the answer is added to the
/// class of the window's root view controller, which is who iPadOS asks.
enum PointerLock {
    private static var wanted = false
    private static var patched: Set<ObjectIdentifier> = []

    static func set(_ on: Bool) {
        wanted = on
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows {
            guard let root = window.rootViewController else { continue }
            let kind: AnyClass = type(of: root)
            if patched.insert(ObjectIdentifier(kind)).inserted {
                let answer: @convention(block) (UIViewController) -> Bool = { _ in wanted }
                class_replaceMethod(kind, #selector(getter: UIViewController.prefersPointerLocked), imp_implementationWithBlock(answer), "B@:")
            }
            root.setNeedsUpdateOfPrefersPointerLocked()
        }
    }

    /// iPadOS only locks the pointer to an app that fills the screen: in a window (Stage Manager, or iPadOS 26's windows)
    /// the request is ignored and the system pointer stays separate from the Mac's (#18). An iPhone never locks it, and
    /// its apps are always full screen, so the hint is for iPad only.
    static var refused: Bool {
        guard Device.isPad, wanted, GCMouse.current != nil else { return false }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.activationState == .foregroundActive }
        return !scenes.isEmpty && !scenes.contains { $0.pointerLockState?.isLocked == true }
    }
}

/// A Magic Keyboard's trackpad or a mouse, while a Mac is running. GameController gives the raw motion,
/// which macOS then accelerates as it would for its own mouse.
final class HardwareMouse {
    static let shared = HardwareMouse()
    static let speedKey = "henge.mouse.speed"
    static let reverseKey = "henge.mouse.reverse"
    static let scrollSpeedKey = "henge.mouse.scrollSpeed"
    static let smoothScrollKey = "henge.mouse.smoothScroll"

    private var observers: [NSObjectProtocol] = []
    private var mice: [GCMouse] = []
    private var buttons = PhysicalMouseButtons(swapsRightAndMiddle: false)
    private var buttonsLogged = 0
    private var restX: Float = 0, restY: Float = 0
    private var speed: Float = 1
    private var reverse = false
    private var scrollsLogged = 0 // the first few, to see what a device's raw values look like
    private var lastScrollFirst: Float = 0, lastScrollSecond: Float = 0
    private var smooth = true
    /* Smooth scrolling: two fingers on the emulated Magic Trackpad 2, where they are (sensor units) and when they lift. */
    private var scrolling = false
    private var fingerX = 0.0, fingerY = 0.0
    private var lift: DispatchWorkItem?
    private static let scrollFingers: (Int32, Int32) = (12, 13) /* the touchscreen's are 1-5, right-click's 14-15 */
    private static let fingerGap = 900.0 /* about 18 mm apart, as two fingers rest */
    private static let edge = 160.0
    private static let sensorW = 8134.0, sensorH = 5206.0 /* the Magic Trackpad 2 sensor, as Trackpad.swift (HV_TP_SENSOR_*) */

    func start() {
        let defaults = UserDefaults.standard
        speed = defaults.object(forKey: Self.speedKey) == nil ? 1 : Float(defaults.double(forKey: Self.speedKey))
        reverse = defaults.bool(forKey: Self.reverseKey)
        releaseButtons()
        let swapButtons = defaults.bool(forKey: PhysicalMouseButtons.swapKey)
        buttons = PhysicalMouseButtons(swapsRightAndMiddle: swapButtons)
        buttonsLogged = 0
        HengeLog.log("input", "physical mouse: swap right/middle \(swapButtons ? "on" : "off")")
        lastScrollFirst = 0
        lastScrollSecond = 0
        smooth = defaults.object(forKey: Self.smoothScrollKey) as? Bool ?? true
        HengeLog.log("input", "hardware scrolling: \(smooth ? "smooth (trackpad fingers)" : "wheel")")
        GCMouse.mice().forEach(attach)
        observers.append(NotificationCenter.default.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] note in
            if let mouse = note.object as? GCMouse { self?.attach(mouse) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let mouse = note.object as? GCMouse else { return }
            self.releaseButtons()
            self.mice.removeAll { $0 === mouse }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIPointerLockState.didChangeNotification, object: nil, queue: .main) { note in
            // The scene comes in the user info: the notification's object isn't it.
            let scene = note.userInfo?[UIPointerLockState.sceneUserInfoKey] as? UIScene
            let locked = scene?.pointerLockState?.isLocked ?? false
            HengeLog.log("input", "pointer lock: \(locked ? "on" : "off")")
        })
        PointerLock.set(true)
    }

    func stop() {
        PointerLock.set(false)
        endScroll()
        releaseButtons()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        for mouse in mice {
            guard let input = mouse.mouseInput else { continue }
            input.mouseMovedHandler = nil
            input.leftButton.pressedChangedHandler = nil
            input.rightButton?.pressedChangedHandler = nil
            input.middleButton?.pressedChangedHandler = nil
            input.scroll.valueChangedHandler = nil
        }
        mice.removeAll()
    }

    func releaseButtons() {
        for button in buttons.releaseAll() { henge_vm_mouse_button(button, 0) }
    }

    private func attach(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput, !mice.contains(where: { $0 === mouse }) else { return }
        mice.append(mouse)
        HengeLog.log("input", "mouse: \(mouse.vendorName ?? "?"), right button \(input.rightButton != nil), middle \(input.middleButton != nil)")
        input.mouseMovedHandler = { [weak self] _, dx, dy in self?.moved(dx, dy) }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in self?.button(0, pressed) }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in self?.button(1, pressed) }
        input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in self?.button(2, pressed) }
        input.scroll.valueChangedHandler = { [weak self] _, first, second in self?.scrolled(first, second) }
    }

    /// GameController's Y runs upward. What doesn't make a whole step yet waits for the next move.
    private func moved(_ dx: Float, _ dy: Float) {
        restX += dx * speed
        restY -= dy * speed
        let x = restX.rounded(), y = restY.rounded()
        guard x != 0 || y != 0 else { return }
        restX -= x
        restY -= y
        henge_vm_mouse_move(Int32(x), Int32(y))
    }

    private func button(_ physicalButton: Int32, _ pressed: Bool) {
        guard let guestButton = buttons.event(physicalButton, pressed: pressed) else { return }
        if buttonsLogged < 32 {
            buttonsLogged += 1
            HengeLog.log("input", "physical mouse button: raw=\(physicalButton) guest=\(guestButton) \(pressed ? "down" : "up")")
        }
        henge_vm_mouse_button(guestButton, pressed ? 1 : 0)
        if !pressed { StickyKeys.shared.releaseAll() }
    }

    /// GameController puts vertical motion on the first axis and horizontal on the second.
    /// macOS accelerates wheel units roughly quadratically, so use a tunable square root
    /// and cap each event to keep a small pad gesture from jumping across a page.
    private func scrolled(_ first: Float, _ second: Float) {
        // GameController reports both axis states when either one changes. On a
        // Magic Keyboard it calls us twice per movement, with one stale axis in
        // each call; sending both values doubles the scroll and adds sideways drift.
        let verticalChanged = first != lastScrollFirst
        let horizontalChanged = second != lastScrollSecond
        lastScrollFirst = first
        lastScrollSecond = second
        if smooth && henge_vm_trackpad_ready() != 0 {
            fingerScroll(vertical: verticalChanged ? first : 0, horizontal: horizontalChanged ? second : 0, raw: (first, second))
            return
        }
        let mostlyVertical = abs(first) > 2 * abs(second)
        let mostlyHorizontal = abs(second) > 2 * abs(first)
        let verticalRaw = verticalChanged && !mostlyHorizontal ? -first : 0
        let horizontalRaw = horizontalChanged && !mostlyVertical ? second : 0
        let defaults = UserDefaults.standard
        let configured = defaults.object(forKey: Self.scrollSpeedKey) == nil
            ? 0.3 : defaults.double(forKey: Self.scrollSpeedKey)
        let scale = Float(configured.isFinite ? min(max(configured, 0.1), 1.5) : 0.3)
        let way: Int32 = reverse ? -1 : 1
        let horizontal = way * Self.wheelUnits(horizontalRaw, scale: scale)
        let vertical = way * Self.wheelUnits(verticalRaw, scale: scale)
        if scrollsLogged < 24 {
            scrollsLogged += 1
            HengeLog.log("input", "scroll raw: \(first), \(second); units: \(horizontal), \(vertical)")
        }
        if horizontal != 0 || vertical != 0 { henge_vm_mouse_scroll(horizontal, vertical) }
    }

    /// Scrolling as a Mac's own trackpad does it: two fingers moving on the emulated Magic Trackpad 2, so macOS scrolls
    /// pixel by pixel, with its own momentum and rubber band, instead of a wheel's steps. Fingers go down with the first
    /// movement, on the side of the pad they move away from (room for a long swipe), follow every movement, and lift
    /// 50 ms after the last (so macOS sees the speed at lift-off and coasts). One that reaches the pad's edge lifts and
    /// goes down again on the other side, as a hand does. The directions match the wheel's: wheel up is fingers up.
    private func fingerScroll(vertical: Float, horizontal: Float, raw: (Float, Float)) {
        guard vertical.isFinite, horizontal.isFinite, vertical != 0 || horizontal != 0 else { return }
        let configured = UserDefaults.standard.object(forKey: Self.scrollSpeedKey) == nil
            ? 0.3 : UserDefaults.standard.double(forKey: Self.scrollSpeedKey)
        let scale = configured.isFinite ? min(max(configured, 0.1), 1.5) : 0.3
        let k = 40 * scale * (reverse ? -1 : 1) /* sensor units per GameController unit: 12 at the default speed */
        let dx = -Double(horizontal) * k, dy = Double(vertical) * k
        let ts = Self.nowMs()
        if !scrolling { beginScroll(dx, dy, ts) }
        var x = fingerX + dx, y = fingerY + dy
        let half = Self.fingerGap / 2
        if x < Self.edge + half || x > Self.sensorW - Self.edge - half || y < Self.edge || y > Self.sensorH - Self.edge {
            endScroll(ts)
            beginScroll(dx, dy, ts &+ 1)
            x = fingerX + dx
            y = fingerY + dy
        }
        fingerX = x
        fingerY = y
        let (a, b) = Self.scrollFingers
        henge_vm_touch(a, 1, Int32(x - half), Int32(y), ts &+ 2)
        henge_vm_touch(b, 1, Int32(x + half), Int32(y), ts &+ 2)
        henge_vm_touch_frame(ts &+ 2)
        if scrollsLogged < 24 {
            scrollsLogged += 1
            HengeLog.log("input", "scroll raw: \(raw.0), \(raw.1); fingers by \(Int(dx)), \(Int(dy)) to \(Int(x)),\(Int(y))")
        }
        lift?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.endScroll() }
        lift = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    /// Two fingers down where a movement of (dx, dy) has the most room.
    private func beginScroll(_ dx: Double, _ dy: Double, _ ts: UInt32) {
        let half = Self.fingerGap / 2
        let left = Self.edge + half + 100, right = Self.sensorW - Self.edge - half - 100
        let top = Self.edge + 100, bottom = Self.sensorH - Self.edge - 100
        fingerX = abs(dx) < 1 ? Self.sensorW / 2 : dx > 0 ? left : right
        fingerY = abs(dy) < 1 ? Self.sensorH / 2 : dy > 0 ? top : bottom
        let (a, b) = Self.scrollFingers
        henge_vm_touch(a, 0, Int32(fingerX - half), Int32(fingerY), ts)
        henge_vm_touch(b, 0, Int32(fingerX + half), Int32(fingerY), ts)
        scrolling = true
    }

    private func endScroll(_ ts: UInt32? = nil) {
        lift?.cancel()
        lift = nil
        guard scrolling else { return }
        scrolling = false
        let (a, b) = Self.scrollFingers
        let t = ts ?? Self.nowMs()
        henge_vm_touch(a, 2, 0, 0, t)
        henge_vm_touch(b, 2, 0, 0, t)
    }

    /// The touch reports' clock: ms of uptime, as UITouch timestamps (the touchscreen's fingers) count.
    private static func nowMs() -> UInt32 { UInt32(truncatingIfNeeded: Int(CACurrentMediaTime() * 1000)) }

    private static func wheelUnits(_ value: Float, scale: Float) -> Int32 {
        guard value.isFinite else { return 0 }
        let units = Int32(min(32, (22 * scale * abs(value).squareRoot()).rounded()))
        return value < 0 ? -units : units
    }
}
