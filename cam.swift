import AVFoundation
import AppKit
import Foundation

let camVersion = "0.1.0"

// MARK: - Args

var outputPath: String?
var deviceQuery: String?
var listOnly = false
var noInline = false

let argv = CommandLine.arguments.dropFirst()
var ai = argv.startIndex
while ai < argv.endIndex {
    let arg = argv[ai]
    switch arg {
    case "-o", "--output":
        ai = argv.index(after: ai)
        guard ai < argv.endIndex else {
            FileHandle.standardError.write(Data("cam: -o needs a value\n".utf8)); exit(2)
        }
        outputPath = argv[ai]
    case "-d", "--device":
        ai = argv.index(after: ai)
        guard ai < argv.endIndex else {
            FileHandle.standardError.write(Data("cam: -d needs a value\n".utf8)); exit(2)
        }
        deviceQuery = argv[ai]
    case "--list":
        listOnly = true
    case "--no-inline":
        noInline = true
    case "-v", "--version":
        print("cam \(camVersion)")
        exit(0)
    case "-h", "--help":
        print("""
        cam — viewfinder + capture from a Mac camera (incl. iPhone Continuity Camera).

        Default save location: ~/Pictures/cam/cam-YYYYMMDD-HHMMSS.jpg

          cam                      capture, save to ~/Pictures/cam/
          cam photo.jpg            save as ./photo.jpg in current directory
          cam -o ~/Desktop/x.jpg   save at a specific path
          cam --no-inline          skip inline render and Quick Look preview
          cam -d, --device <name>  pick a camera by substring of its name
          cam --list               list available cameras
          cam -v, --version        print version
          cam -h, --help           print this help

        In the viewfinder window:
          space / return           capture
          esc / q                  cancel
        """)
        exit(0)
    default:
        if arg.hasPrefix("-") {
            FileHandle.standardError.write(Data("cam: unknown option: \(arg)\n".utf8))
            exit(2)
        }
        outputPath = arg
    }
    ai = argv.index(after: ai)
}

// MARK: - Camera discovery

let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.continuityCamera, .external, .builtInWideAngleCamera, .deskViewCamera],
    mediaType: .video,
    position: .unspecified
)

if listOnly {
    for d in discovery.devices {
        print("\(d.localizedName)  [\(d.deviceType.rawValue)]")
    }
    exit(0)
}

let chosenDevice: AVCaptureDevice? = {
    if let q = deviceQuery?.lowercased() {
        return discovery.devices.first { $0.localizedName.lowercased().contains(q) }
    }
    if let iphone = discovery.devices.first(where: { $0.deviceType == .continuityCamera }) {
        return iphone
    }
    if let byName = discovery.devices.first(where: { $0.localizedName.lowercased().contains("iphone") }) {
        return byName
    }
    return discovery.devices.first
}()

guard let device = chosenDevice else {
    FileHandle.standardError.write(Data("cam: no camera found. If using iPhone Continuity Camera, make sure the phone is unlocked, nearby, signed in to the same Apple Account, with Bluetooth and Wi-Fi on.\n".utf8))
    exit(1)
}

// MARK: - Camera permission

let auth = AVCaptureDevice.authorizationStatus(for: .video)
if auth == .notDetermined {
    let sem = DispatchSemaphore(value: 0)
    AVCaptureDevice.requestAccess(for: .video) { _ in sem.signal() }
    sem.wait()
}
if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
    FileHandle.standardError.write(Data("cam: camera access denied. Grant it in System Settings -> Privacy & Security -> Camera.\n".utf8))
    exit(1)
}

// MARK: - Output path

let outputURL: URL = {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    if let p = outputPath {
        let expanded = (p as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, relativeTo: cwd).standardizedFileURL
    }
    let pictures = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/cam")
    try? FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyyMMdd-HHmmss"
    return pictures.appendingPathComponent("cam-\(fmt.string(from: Date())).jpg")
}()

// MARK: - Inline render (iTerm2 OSC 1337) with Quick Look fallback

func showCapture(_ url: URL) {
    guard let data = try? Data(contentsOf: url) else { return }
    let inTmux = ProcessInfo.processInfo.environment["TMUX"] != nil
    let escStart = inTmux ? "\u{1B}Ptmux;\u{1B}\u{1B}" : "\u{1B}"
    let escEnd = inTmux ? "\u{07}\u{1B}\\" : "\u{07}"
    let name = url.lastPathComponent
    let nameB64 = Data(name.utf8).base64EncodedString()
    let dataB64 = data.base64EncodedString()
    let payload = "\(escStart)]1337;File=name=\(nameB64);size=\(data.count);inline=1;preserveAspectRatio=1:\(dataB64)\(escEnd)\n"
    let bytes = Data(payload.utf8)

    if let tty = FileHandle(forWritingAtPath: "/dev/tty") {
        tty.write(bytes)
        try? tty.close()
        return
    }

    let task = Process()
    task.launchPath = "/usr/bin/qlmanage"
    task.arguments = ["-p", url.path]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
}

// MARK: - Capture delegate

final class CaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let outputURL: URL
    let preview: Bool
    init(outputURL: URL, preview: Bool) {
        self.outputURL = outputURL
        self.preview = preview
    }
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            FileHandle.standardError.write(Data("cam: capture error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        guard let data = photo.fileDataRepresentation() else {
            FileHandle.standardError.write(Data("cam: no photo data returned\n".utf8))
            exit(1)
        }
        do {
            try data.write(to: outputURL)
            FileHandle.standardError.write(Data("cam: saved \(outputURL.path)\n".utf8))
            if preview { showCapture(outputURL) }
        } catch {
            FileHandle.standardError.write(Data("cam: write error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

// MARK: - Preview view

final class PreviewView: NSView {
    var onKey: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
}

// MARK: - Build capture session

let captureSession = AVCaptureSession()
captureSession.sessionPreset = .photo

do {
    let input = try AVCaptureDeviceInput(device: device)
    if captureSession.canAddInput(input) {
        captureSession.addInput(input)
    } else {
        FileHandle.standardError.write(Data("cam: cannot add input from \(device.localizedName)\n".utf8))
        exit(1)
    }
} catch {
    FileHandle.standardError.write(Data("cam: input error: \(error.localizedDescription)\n".utf8))
    exit(1)
}

let photoOutput = AVCapturePhotoOutput()
guard captureSession.canAddOutput(photoOutput) else {
    FileHandle.standardError.write(Data("cam: cannot add photo output\n".utf8))
    exit(1)
}
captureSession.addOutput(photoOutput)

let delegate = CaptureDelegate(outputURL: outputURL, preview: !noInline)

// MARK: - Window & app

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
previewLayer.videoGravity = .resizeAspect

let containerLayer = CALayer()
containerLayer.backgroundColor = NSColor.black.cgColor

let view = PreviewView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
view.wantsLayer = true
view.layer = containerLayer
containerLayer.addSublayer(previewLayer)
previewLayer.frame = view.bounds
previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

view.onKey = { event in
    switch event.keyCode {
    case 49 /* space */, 36 /* return */, 76 /* numpad enter */:
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    case 53 /* escape */, 12 /* q */:
        NSApp.terminate(nil)
    default:
        break
    }
}

let window = NSWindow(
    contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
    styleMask: [.titled, .closable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "cam - \(device.localizedName)  -  space/return: capture  -  esc: cancel"
window.contentView = view
window.makeFirstResponder(view)
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

DispatchQueue.global(qos: .userInitiated).async {
    captureSession.startRunning()
}

withExtendedLifetime(delegate) {
    app.run()
}
