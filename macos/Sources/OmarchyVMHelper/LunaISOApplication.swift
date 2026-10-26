import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

enum LunaISOLaunchError: LocalizedError {
    case invalidISOPath
    case invalidMemory
    case invalidCPUCount
    case missingLauncher

    var errorDescription: String? {
        switch self {
        case .invalidISOPath: "Choisissez un fichier ISO avec un chemin absolu valide."
        case .invalidMemory: "La mémoire doit être un nombre entier entre 2 048 et 65 536 MiB."
        case .invalidCPUCount: "Le nombre de cœurs doit être un entier entre 1 et 64."
        case .missingLauncher: "Le lanceur try-luna manque dans l’application. Reconstruisez l’application avec make app."
        }
    }
}

struct LunaISOLaunchRequest: Equatable {
    let isoPath: String?
    let memoryMiB: Int
    let cpuCount: Int

    init(isoPath: String?, memoryMiB: String, cpuCount: String) throws {
        if let isoPath {
            guard isoPath.hasPrefix("/"), !isoPath.contains("\n"), !isoPath.contains("\r"),
                  !isoPath.contains("\0") else { throw LunaISOLaunchError.invalidISOPath }
        }
        guard !memoryMiB.isEmpty, memoryMiB.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let memory = Int(memoryMiB), (2048...65536).contains(memory) else {
            throw LunaISOLaunchError.invalidMemory
        }
        guard !cpuCount.isEmpty, cpuCount.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let cpus = Int(cpuCount), (1...64).contains(cpus) else {
            throw LunaISOLaunchError.invalidCPUCount
        }
        self.isoPath = isoPath
        self.memoryMiB = memory
        self.cpuCount = cpus
    }

    var arguments: [String] {
        var result = ["run"]
        if let isoPath { result += ["--iso", isoPath] }
        return result + ["--memory", String(memoryMiB), "--cpus", String(cpuCount), "--name", "default"]
    }
}

@MainActor
private final class LunaISOApplicationController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var isoURL: URL?
    private var process: Process?
    private var outputURL: URL?
    private var runningGuest = false
    private let isoLabel = NSTextField(wrappingLabelWithString: "Aucun ISO sélectionné")
    private let memoryField = NSTextField(string: "4096")
    private let cpuField = NSTextField(string: String(min(4, ProcessInfo.processInfo.activeProcessorCount)))
    private let statusLabel = NSTextField(wrappingLabelWithString: "Choisissez un ISO LunaOS x86_64 pour commencer.")
    private let logView = NSTextView()
    private var actionButtons: [NSButton] = []
    private var resourceFields: [NSTextField] { [memoryField, cpuField] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenu()
        makeWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Try Luna")
        appMenu.addItem(withTitle: "À propos de Try Luna", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quitter Try Luna", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    private func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Try Luna"
        window.minSize = NSSize(width: 740, height: 720)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        let title = NSTextField(labelWithString: "Try Luna")
        title.font = .systemFont(ofSize: 32, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "Un espace pour découvrir LunaOS sur votre Mac.")
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = .secondaryLabelColor
        let introduction = NSTextField(wrappingLabelWithString: "L’ISO x86_64 s’exécute dans une machine virtuelle QEMU. Sur un Mac Apple Silicon, son émulation est plus lente qu’une VM ARM native. Aucune image ARM LunaOS n’est actuellement disponible.")
        introduction.textColor = .secondaryLabelColor
        introduction.font = .systemFont(ofSize: 13)

        let chooseButton = button("Choisir un ISO…", action: #selector(chooseISO))
        isoLabel.textColor = .secondaryLabelColor
        isoLabel.lineBreakMode = .byTruncatingMiddle
        isoLabel.maximumNumberOfLines = 2
        let isoRow = row([chooseButton, isoLabel])
        isoLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        memoryField.placeholderString = "4096"
        memoryField.setAccessibilityLabel("Mémoire en MiB")
        cpuField.setAccessibilityLabel("Nombre de cœurs")
        memoryField.widthAnchor.constraint(equalToConstant: 90).isActive = true
        cpuField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let resourceRow = row([NSTextField(labelWithString: "Mémoire (MiB)"), memoryField,
                               NSTextField(labelWithString: "Cœurs"), cpuField])
        let installer = button("Démarrer avec l’ISO", action: #selector(launchISO))
        installer.bezelColor = .systemPurple
        let installed = button("Démarrer le disque existant", action: #selector(launchInstalledDisk))
        let launchRow = row([installer, installed])
        let diskDescription = NSTextField(wrappingLabelWithString: "Le disque virtuel LunaOS est conservé entre les sessions. Après installation, le disque a priorité sur l’ISO. Utilisez ensuite le démarrage du disque existant.")
        diskDescription.font = .systemFont(ofSize: 12)
        diskDescription.textColor = .secondaryLabelColor

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        logView.isEditable = false
        logView.isSelectable = true
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textContainerInset = NSSize(width: 10, height: 10)
        logView.autoresizingMask = [.width]
        logView.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.documentView = logView
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        let diagnose = button("Vérifier QEMU", action: #selector(diagnose))
        let releases = NSButton(title: "Releases LunaOS ↗", target: self, action: #selector(openReleases))
        releases.bezelStyle = .rounded
        let footer = row([diagnose, releases])
        let prerequisite = NSTextField(wrappingLabelWithString: "QEMU requis. Avec Homebrew : brew install qemu")
        prerequisite.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        prerequisite.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, subtitle, introduction, isoRow, resourceRow,
                                       launchRow, diskDescription, statusLabel, scroll, footer, prerequisite])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(4, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            introduction.widthAnchor.constraint(equalTo: stack.widthAnchor),
            diskDescription.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            isoRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let result = NSStackView(views: views)
        result.orientation = .horizontal
        result.alignment = .centerY
        result.spacing = 12
        return result
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let result = NSButton(title: title, target: self, action: action)
        result.bezelStyle = .rounded
        actionButtons.append(result)
        return result
    }

    @objc private func chooseISO() {
        let panel = NSOpenPanel()
        panel.title = "Choisir un ISO LunaOS x86_64"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "iso") ?? .data]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                self?.isoURL = url
                self?.isoLabel.stringValue = url.path
                self?.statusLabel.stringValue = "ISO sélectionné. La VM démarrera uniquement après votre clic."
                self?.statusLabel.textColor = .labelColor
            }
        }
    }

    @objc private func launchISO() {
        guard let isoURL else {
            statusLabel.stringValue = "Choisissez d’abord un fichier ISO LunaOS."
            statusLabel.textColor = .systemOrange
            return
        }
        launch(isoPath: isoURL.path)
    }

    @objc private func launchInstalledDisk() { launch(isoPath: nil) }

    private func launch(isoPath: String?) {
        do {
            let request = try LunaISOLaunchRequest(isoPath: isoPath, memoryMiB: memoryField.stringValue,
                                                 cpuCount: cpuField.stringValue)
            try start(arguments: request.arguments, guest: true)
        } catch { showError(error.localizedDescription) }
    }

    @objc private func diagnose() {
        do { try start(arguments: ["doctor"], guest: false) }
        catch { showError(error.localizedDescription) }
    }

    @objc private func openReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/gregpavoine/LunaOS-iso/releases")!)
    }

    private func start(arguments: [String], guest: Bool) throws {
        guard process == nil else { return }
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("scripts/try-luna"),
              FileManager.default.isReadableFile(atPath: script.path) else {
            throw LunaISOLaunchError.missingLauncher
        }
        var logTemplate = Array(FileManager.default.temporaryDirectory.appendingPathComponent("try-luna-output.XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&logTemplate)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let logURL = URL(fileURLWithPath: String(cString: logTemplate))
        let logHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? logHandle.close() }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/bash")
        child.arguments = [script.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        child.environment = environment
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = logHandle
        child.standardError = logHandle
        child.terminationHandler = { [weak self] completed in
            let code = completed.terminationStatus
            Task { @MainActor [weak self] in self?.finished(status: code) }
        }
        logView.string = ""
        runningGuest = guest
        process = child
        outputURL = logURL
        setBusy(true)
        statusLabel.textColor = .labelColor
        statusLabel.stringValue = guest ? "VM en cours. Fermez sa fenêtre QEMU pour terminer la session." : "Vérification de QEMU…"
        do { try child.run() }
        catch {
            try? FileManager.default.removeItem(at: logURL)
            outputURL = nil
            process = nil
            setBusy(false)
            throw error
        }
    }

    private func appendLog(_ message: String) {
        logView.textStorage?.append(NSAttributedString(string: message, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]))
        if logView.string.utf16.count > 131072 {
            logView.textStorage?.deleteCharacters(in: NSRange(location: 0, length: logView.string.utf16.count - 65536))
        }
        logView.scrollToEndOfDocument(nil)
    }

    private func finished(status: Int32) {
        let guest = runningGuest
        if let outputURL {
            do {
                let handle = try FileHandle(forReadingFrom: outputURL)
                defer { try? handle.close() }
                let size = try handle.seekToEnd()
                try handle.seek(toOffset: size > 131072 ? size - 131072 : 0)
                if let data = try handle.readToEnd() { appendLog(String(decoding: data, as: UTF8.self)) }
            } catch { appendLog("Impossible de lire le journal : \(error.localizedDescription)\n") }
            try? FileManager.default.removeItem(at: outputURL)
        }
        process = nil
        outputURL = nil
        runningGuest = false
        setBusy(false)
        statusLabel.textColor = status == 0 ? .labelColor : .systemRed
        if status == 0 {
            statusLabel.stringValue = guest ? "Session terminée. Le disque virtuel est conservé." : "Vérification terminée. Consultez le résultat ci-dessus."
        } else {
            statusLabel.stringValue = "Échec (code \(status)). Le détail est affiché ci-dessus."
        }
    }

    private func setBusy(_ busy: Bool) {
        for button in actionButtons { button.isEnabled = !busy }
        for field in resourceFields { field.isEnabled = !busy }
    }

    private func showError(_ message: String) {
        statusLabel.stringValue = message
        statusLabel.textColor = .systemRed
        appendLog(message + "\n")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard process?.isRunning == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = runningGuest ? "Une machine virtuelle est encore ouverte." : "Un diagnostic est en cours."
        alert.informativeText = runningGuest ? "Fermez la fenêtre QEMU après avoir arrêté LunaOS, puis quittez Try Luna." : "Attendez la fin du diagnostic avant de quitter Try Luna."
        alert.addButton(withTitle: "Revenir à Try Luna")
        alert.runModal()
        return .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        applicationShouldTerminate(NSApp) == .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
func runLunaISOApplication() -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let controller = LunaISOApplicationController()
    application.delegate = controller
    withExtendedLifetime(controller) { application.run() }
    exit(0)
}
