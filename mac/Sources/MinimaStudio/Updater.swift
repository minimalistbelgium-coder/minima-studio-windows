import Foundation
import AppKit
import Supabase

/// Mises à jour de l'app : l'admin publie une version, les autres Mac l'installent en un clic.
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var latest: AppRelease?
    @Published private(set) var installing = false
    @Published private(set) var progressText: String?
    @Published var error: String?

    private var timer: Timer?

    var updateAvailable: AppRelease? {
        guard let l = latest, AppVersion.isNewer(l.version, than: AppVersion.current) else { return nil }
        return l
    }

    func start() {
        Task { await check() }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func check() async {
        do {
            let rows: [AppRelease] = try await supa.from("app_releases").select()
                .order("created_at", ascending: false).limit(20).execute().value
            latest = rows.max { a, b in AppVersion.isNewer(b.version, than: a.version) }
        } catch {
            // Pas bloquant
        }
    }

    static func publicURL(_ path: String) -> URL? {
        try? supa.storage.from("releases").getPublicURL(path: path)
    }

    /// Lien stable vers le dernier .dmg, à envoyer aux nouveaux monteurs.
    static var latestDmgURL: URL? { publicURL("MinimaStudio.dmg") }

    // MARK: Installation

    func install(_ release: AppRelease, tracker: Tracker) async {
        guard let url = Self.publicURL(release.zip_path) else { return }
        installing = true
        error = nil
        progressText = "Téléchargement…"
        do {
            let (tmpFile, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.message("Téléchargement impossible") }

            let work = FileManager.default.temporaryDirectory.appendingPathComponent("MinimaUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: tmpFile, to: zip)

            progressText = "Vérification…"
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.message("Archive invalide")
            }
            try Self.verifySignature(newApp)

            progressText = "Installation…"
            await tracker.endSession(deduct: 0, reason: "Mise à jour")

            let dest = Bundle.main.bundleURL
            let script = work.appendingPathComponent("install.sh")
            let sh = """
            #!/bin/bash
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
            rm -rf "\(dest.path).old"
            mv "\(dest.path)" "\(dest.path).old" && mv "\(newApp.path)" "\(dest.path)" && rm -rf "\(dest.path).old"
            xattr -dr com.apple.quarantine "\(dest.path)" 2>/dev/null
            open "\(dest.path)"
            """
            try sh.write(to: script, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [script.path]
            try p.run()
            NSApp.terminate(nil)
        } catch {
            installing = false
            progressText = nil
            self.error = (error as? UpdateError)?.text ?? error.localizedDescription
        }
    }

    enum UpdateError: Error {
        case message(String)
        var text: String { if case .message(let m) = self { return m }; return "" }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 { throw UpdateError.message("Échec de \((tool as NSString).lastPathComponent)") }
        return out
    }

    /// Refuse une app non signée, ou signée par une autre équipe que l'app actuelle.
    static func verifySignature(_ app: URL) throws {
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            throw UpdateError.message("Signature de la mise à jour invalide")
        }
        let current = teamID(Bundle.main.bundleURL)
        if let current, teamID(app) != current {
            throw UpdateError.message("La mise à jour n'est pas signée par Minimalist Belgium")
        }
    }

    static func teamID(_ app: URL) -> String? {
        guard let out = try? run("/usr/bin/codesign", ["-dv", "--verbose=2", app.path]) else { return nil }
        for line in out.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let v = line.replacingOccurrences(of: "TeamIdentifier=", with: "")
            return v == "not set" ? nil : v
        }
        return nil
    }

    // MARK: Publication (admin)

    /// Envoie le .zip (et le .dmg s'il est à côté) produits par release.sh, puis annonce la version.
    func publish(zipURL: URL, version: String, notes: String) async throws {
        let bucket = supa.storage.from("releases")
        let zipPath = "v\(version)/MinimaStudio-\(version).zip"
        progressText = "Envoi de la mise à jour…"
        try await bucket.upload(zipPath, fileURL: zipURL, options: FileOptions(contentType: "application/zip", upsert: true))

        var dmgPath: String?
        let dmgURL = zipURL.deletingPathExtension().appendingPathExtension("dmg")
        if FileManager.default.fileExists(atPath: dmgURL.path) {
            progressText = "Envoi de l'installeur…"
            let p = "v\(version)/MinimaStudio-\(version).dmg"
            try await bucket.upload(p, fileURL: dmgURL, options: FileOptions(contentType: "application/x-apple-diskimage", upsert: true))
            try await bucket.upload("MinimaStudio.dmg", fileURL: dmgURL, options: FileOptions(cacheControl: "60", contentType: "application/x-apple-diskimage", upsert: true))
            dmgPath = p
        }

        try await supa.from("app_releases").upsert(
            AppReleaseInsert(version: version, zip_path: zipPath, dmg_path: dmgPath, notes: notes.isEmpty ? nil : notes),
            onConflict: "version"
        ).execute()
        progressText = "Nettoyage des anciennes versions…"
        _ = try? await cleanup(keep: version)
        progressText = nil
        await check()
    }

    /// Supprime les anciennes versions (fiches et fichiers), sauf celle indiquée. Renvoie le nombre de fichiers supprimés.
    @discardableResult
    func cleanup(keep version: String) async throws -> Int {
        let bucket = supa.storage.from("releases")
        let keepFolder = "v\(version)"
        var removed = 0
        let folders = try await bucket.list()
        for f in folders where f.name.hasPrefix("v") && f.name != keepFolder {
            let files = try await bucket.list(path: f.name)
            let paths = files.map { "\(f.name)/\($0.name)" }
            if !paths.isEmpty {
                _ = try await bucket.remove(paths: paths)
                removed += paths.count
            }
        }
        try await supa.from("app_releases").delete().neq("version", value: version).execute()
        return removed
    }
}
