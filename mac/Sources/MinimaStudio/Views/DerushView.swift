import SwiftUI
import AppKit
import AVFoundation

/// Dérush hors ligne : syncro des caméras sur les micros, multicam selon qui parle,
/// micros coupés pendant que la personne écoute. Le moteur est livré dans l'app (Resources/derush).
@MainActor
final class DerushModel: ObservableObject {
    enum Phase { case idle, scanning, config, running, done, finalizing, finalized, failed }

    struct Cam: Identifiable { let id = UUID(); var label: String; var files: [String]; var role: String; var thumb: String? = nil }
    struct Mic: Identifiable { let id = UUID(); var label: String; var folder: String; var path: String; var use: Bool; var duration: Double; var speaker: String; var preview: String? = nil }

    @Published var phase: Phase = .idle
    @Published var folder: URL?
    @Published var name = ""
    @Published var cams: [Cam] = []
    @Published var mics: [Mic] = []
    @Published var wide = "overlap"
    @Published var pct: Double = 0
    @Published var message = ""
    @Published var logs: [String] = []
    @Published var warnings: [String] = []
    @Published var error: String?
    @Published var xmlPath: String?
    @Published var planPath: String?
    @Published var stats: [String: Any] = [:]
    @Published var finalText = ""
    @Published var finalFile: String?
    @Published var playing: Int?
    private var player: AVAudioPlayer?
    private var playerDelegate: PlayerEnd?

    var speakers: [String] { mics.filter(\.use).map { $0.speaker.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    // MARK: moteur
    static var engineDir: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        for d in [res.appendingPathComponent("derush/\(arch)/minima-derush"), res.appendingPathComponent("derush/minima-derush")] {
            if FileManager.default.isExecutableFile(atPath: d.appendingPathComponent("minima-derush").path) { return d }
        }
        return nil
    }

    /// Lance le moteur, transmet les lignes de progression et renvoie le message final « result ».
    func engine(_ args: [String], config: [String: Any]? = nil, onLine: (([String: Any]) -> Void)? = nil) async throws -> [String: Any] {
        guard let dir = Self.engineDir else { throw NSError(domain: "derush", code: 1, userInfo: [NSLocalizedDescriptionKey: "Moteur de dérush introuvable dans l'app."]) }
        var args = args
        if let config {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("minima-derush-\(UUID().uuidString).json")
            try JSONSerialization.data(withJSONObject: config).write(to: url)
            args.append(url.path)
        }
        let p = Process()
        p.executableURL = dir.appendingPathComponent("minima-derush")
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["MINIMA_FFMPEG"] = dir.appendingPathComponent("ffmpeg").path
        env["PYTHONIOENCODING"] = "utf-8"
        p.environment = env
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        return try await withCheckedThrowingContinuation { cont in
            var buffer = Data(); var result: [String: Any]?; var err: String?
            out.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                if chunk.isEmpty { return }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: buffer.startIndex..<nl); buffer.removeSubrange(buffer.startIndex...nl)
                    guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    switch obj["type"] as? String {
                    case "result": result = obj
                    case "error": err = obj["msg"] as? String
                    default: DispatchQueue.main.async { onLine?(obj) }
                    }
                }
            }
            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                if let rest = try? out.fileHandleForReading.readToEnd(), !rest.isEmpty {
                    for l in rest.split(separator: 0x0A) {
                        if let o = try? JSONSerialization.jsonObject(with: Data(l)) as? [String: Any] {
                            if o["type"] as? String == "result" { result = o } else if o["type"] as? String == "error" { err = o["msg"] as? String }
                        }
                    }
                }
                if let result { cont.resume(returning: result) }
                else { cont.resume(throwing: NSError(domain: "derush", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err ?? "Le moteur s'est arrêté (code \(proc.terminationStatus))."])) }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    // MARK: étapes
    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Dossier des rushes de l'épisode"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url; name = url.lastPathComponent; phase = .scanning; error = nil; logs = []; warnings = []
        Task {
            do {
                let r = try await engine(["scan", url.path])
                let rc = (r["cams"] as? [[String: Any]]) ?? []
                let rm = (r["mics"] as? [[String: Any]]) ?? []
                let people = rc.filter { ($0["role"] as? String) != "wide" }.compactMap { $0["label"] as? String }
                cams = rc.map { Cam(label: $0["label"] as? String ?? "", files: $0["files"] as? [String] ?? [],
                                     role: ($0["role"] as? String) == "wide" ? "wide" : ($0["label"] as? String ?? ""), thumb: $0["thumb"] as? String) }
                var k = 0
                mics = rm.map { m in
                    let use = m["use"] as? Bool ?? false
                    let label = m["label"] as? String ?? ""
                    var spk = label
                    if use { spk = k < people.count ? people[k] : label; k += 1 }
                    return Mic(label: label, folder: m["folder"] as? String ?? "", path: m["path"] as? String ?? "", use: use,
                               duration: m["duration"] as? Double ?? 0, speaker: spk, preview: m["preview"] as? String)
                }
                phase = .config
            } catch { self.error = error.localizedDescription; phase = .failed }
        }
    }

    func renameSpeaker(_ i: Int, to v: String) {
        let old = mics[i].speaker
        mics[i].speaker = v
        for j in cams.indices where cams[j].role == old { cams[j].role = v }
    }

    func run() {
        let sp = speakers
        guard !sp.isEmpty else { error = "Coche au moins un micro."; return }
        guard Set(sp).count == sp.count else { error = "Deux micros ont le même nom : chaque micro correspond à une personne."; return }
        guard cams.contains(where: { sp.contains($0.role) }) else { error = "Indique au moins une caméra qui filme une des personnes."; return }
        guard let folder else { return }
        error = nil
        let cfg: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces).isEmpty ? folder.lastPathComponent : name,
            "root": folder.path, "out_dir": folder.path,
            "cams": cams.map { ["label": $0.label, "files": $0.files, "role": $0.role] },
            "mics": mics.map { ["label": $0.label, "path": $0.path, "speaker": $0.speaker.trimmingCharacters(in: .whitespaces), "use": $0.use] },
            "options": ["wide": wide],
        ]
        phase = .running; pct = 0; message = "Démarrage…"; logs = []; warnings = []
        Task {
            do {
                let r = try await engine(["run"], config: cfg) { [weak self] m in
                    guard let self else { return }
                    switch m["type"] as? String {
                    case "step":
                        if let p = m["pct"] as? Double { self.pct = p } else if let p = m["pct"] as? Int { self.pct = Double(p) }
                        if let s = m["msg"] as? String { self.message = s }
                    case "log": if let s = m["msg"] as? String { self.logs.append(s) }
                    case "warning": if let s = m["msg"] as? String { self.warnings.append(s) }
                    default: break
                    }
                }
                xmlPath = r["xml"] as? String; planPath = r["plan"] as? String; stats = r["stats"] as? [String: Any] ?? [:]
                phase = .done
            } catch { self.error = error.localizedDescription; phase = .failed }
        }
    }

    func openInPremiere(_ path: String?) {
        guard let path else { return }
        let url = URL(fileURLWithPath: path)
        let ws = NSWorkspace.shared
        let apps = ws.urlsForApplications(withBundleIdentifier: "com.adobe.PremierePro.27") + ws.urlsForApplications(withBundleIdentifier: "com.adobe.PremierePro.26")
        let candidates = apps.isEmpty ? (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("Adobe Premiere Pro") }
            .compactMap { d -> URL? in (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil))?.first { $0.pathExtension == "app" } }
            .sorted { $0.path > $1.path } ?? [] : apps
        if let appURL = candidates.first {
            ws.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            ws.open(url)
        }
    }

    func finalize() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["prproj"]
        panel.directoryURL = folder
        panel.message = "Projet Premiere enregistré (fermé dans Premiere)"
        guard panel.runModal() == .OK, let url = panel.url, let planPath else { return }
        phase = .finalizing
        Task {
            do {
                let r = try await engine(["finalize", url.path, planPath])
                finalFile = url.path
                finalText = "\(r["multicam"] as? Int ?? 0) plans multicam activés, \(r["muted"] as? Int ?? 0) morceaux de micro coupés pendant que la personne écoute."
                phase = .finalized
            } catch { self.error = error.localizedDescription; phase = .failed }
        }
    }

    /// Écoute l'extrait du micro (préparé par le moteur) pour savoir qui parle dedans.
    func togglePlay(_ i: Int) {
        player?.stop(); player = nil
        if playing == i { playing = nil; return }
        guard let path = mics[i].preview, let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else { playing = nil; return }
        let d = PlayerEnd { [weak self] in Task { @MainActor in self?.playing = nil } }
        p.delegate = d; playerDelegate = d
        player = p; playing = i; p.play()
    }

    /// Fait tourner les noms entre les micros cochés (avec deux micros : les échange).
    func swapMics() {
        let idx = mics.indices.filter { mics[$0].use }
        guard idx.count >= 2 else { return }
        let names = idx.map { mics[$0].speaker }
        for (k, i) in idx.enumerated() { mics[i].speaker = names[(k + 1) % names.count] }
    }

    func reset() { player?.stop(); player = nil; playing = nil; phase = .idle; folder = nil; cams = []; mics = []; error = nil; xmlPath = nil; planPath = nil; finalFile = nil }
}

struct DerushView: View {
    @StateObject private var m = DerushModel()

    var body: some View {
        Page {
            PageHeader(kicker: "Hors ligne · syncro et multicam", title: "Dérush") {
                if m.phase != .idle && m.phase != .running {
                    Button("Nouvel épisode") { m.reset() }.buttonStyle(SecondaryButton())
                }
            }
            content
            if let e = m.error, m.phase != .failed {
                Text(e).font(.system(size: 13)).foregroundStyle(Theme.dangerText)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch m.phase {
        case .idle:
            VStack(alignment: .leading, spacing: 12) {
                Text("Nouvel épisode").font(.system(size: 17, weight: .semibold))
                Muted("Un sous-dossier par caméra, les fichiers son des micros dans le même dossier d'épisode. Le moteur synchronise tout sur les micros, coupe sur la personne qui parle et prépare le projet Premiere (SYNCRO, MULTICAM, MONTAGE). Tout se fait sur ce Mac, sans internet.")
                Button("Choisir le dossier des rushes") { m.pickFolder() }.buttonStyle(PrimaryButton()).padding(.top, 4)
            }.card()
        case .scanning:
            HStack(spacing: 10) { ProgressView().controlSize(.small); Muted("Recherche des caméras et des micros dans \(m.folder?.lastPathComponent ?? "")…") }.card()
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                Text("Ça n'a pas marché").font(.system(size: 17, weight: .semibold))
                Text(m.error ?? "").font(.system(size: 13))
                HStack { Button("Recommencer") { m.reset() }.buttonStyle(SecondaryButton())
                    if !m.cams.isEmpty { Button("Revenir aux réglages") { m.error = nil; m.phase = .config }.buttonStyle(PrimaryButton()) } }
            }.card()
        case .config: config
        case .running:
            VStack(alignment: .leading, spacing: 12) {
                Text(m.name).font(.system(size: 17, weight: .semibold))
                Muted(m.message)
                ProgressView(value: m.pct, total: 100)
                if !m.logs.isEmpty { Text(m.logs.suffix(6).joined(separator: "\n")).font(.system(size: 12)).foregroundStyle(Theme.muted) }
            }.card()
        case .done, .finalizing: done
        case .finalized:
            VStack(alignment: .leading, spacing: 10) {
                Text("Projet prêt").font(.system(size: 17, weight: .semibold))
                Text(m.finalText).font(.system(size: 13.5))
                Muted("\((m.finalFile as NSString?)?.lastPathComponent ?? "") · une copie de sécurité « .avant-minima » est à côté.")
                Button("Rouvrir dans Premiere") { m.openInPremiere(m.finalFile) }.buttonStyle(PrimaryButton())
            }.card()
        }
    }

    private var config: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.folder?.lastPathComponent ?? "").font(.system(size: 17, weight: .semibold))
                    Muted("Vérifie qui filme qui et qui parle dans quel micro")
                }
                Spacer()
                Button("Autre dossier") { m.pickFolder() }.buttonStyle(SecondaryButton()).controlSize(.small)
            }
            FormField(label: "Nom du projet") { TextField("", text: $m.name).input() }
            HStack {
                SectionTitle(text: "Micros")
                Spacer()
                if m.mics.filter(\.use).count >= 2 {
                    Button("⇄ Inverser les micros") { m.swapMics() }.buttonStyle(SecondaryButton()).controlSize(.small)
                }
            }
            ForEach(m.mics.indices, id: \.self) { i in
                HStack(spacing: 12) {
                    Toggle("", isOn: $m.mics[i].use).labelsHidden()
                    if m.mics[i].preview != nil {
                        Button(m.playing == i ? "■ Stop" : "▶ Écouter") { m.togglePlay(i) }
                            .buttonStyle(SecondaryButton()).controlSize(.small).help("Écouter un extrait de ce micro")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.mics[i].label).font(.system(size: 13.5, weight: .medium))
                        Muted("\(m.mics[i].folder)\(m.mics[i].duration > 0 ? " · \(Int(m.mics[i].duration / 60)) min" : "")\(m.mics[i].use ? "" : " · ignoré")")
                    }
                    Spacer()
                    TextField("Qui parle dans ce micro", text: Binding(get: { m.mics[i].speaker }, set: { m.renameSpeaker(i, to: $0) }))
                        .input().frame(width: 200).disabled(!m.mics[i].use)
                }
            }
            SectionTitle(text: "Caméras")
            ForEach(m.cams.indices, id: \.self) { i in
                HStack(spacing: 12) {
                    Group {
                        if let t = m.cams[i].thumb, let img = NSImage(contentsOfFile: t) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        } else { Color.gray.opacity(0.15) }
                    }.frame(width: 128, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.cams[i].label).font(.system(size: 13.5, weight: .medium))
                        Muted("\(m.cams[i].files.count) fichier\(m.cams[i].files.count > 1 ? "s" : "") · \(m.cams[i].files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))")
                    }
                    Spacer()
                    Picker("", selection: $m.cams[i].role) {
                        ForEach(m.speakers, id: \.self) { Text("Filme \($0)").tag($0) }
                        Text("Plan large").tag("wide")
                        Text("Ne pas utiliser").tag("ignore")
                    }.labelsHidden().frame(width: 200)
                }
            }
            FormField(label: "Plan large") {
                Picker("", selection: $m.wide) {
                    Text("Jamais").tag("none")
                    Text("Quand ils parlent en même temps").tag("overlap")
                    Text("Aussi toutes les 30 s dans les longues réponses").tag("overlap+breath")
                }.labelsHidden().frame(maxWidth: 360, alignment: .leading)
            }
            Button("Lancer le dérush") { m.run() }.buttonStyle(PrimaryButton())
        }.card()
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Synchro et découpage prêts").font(.system(size: 17, weight: .semibold))
            if let n = m.stats["shots"] as? Int {
                let avg = m.stats["avg_shot_s"] as? Double ?? 0
                let per = (m.stats["per_angle_pct"] as? [String: Any] ?? [:]).map { "\($0.key) \($0.value) %" }.sorted().joined(separator: " · ")
                Text("\(n) plans, \(String(format: "%.1f", avg)) s en moyenne · \(per)").font(.system(size: 13.5))
            }
            if !m.logs.isEmpty { Text(m.logs.joined(separator: "\n")).font(.system(size: 12)).foregroundStyle(Theme.muted) }
            if !m.warnings.isEmpty { Text(m.warnings.joined(separator: "\n")).font(.system(size: 12.5)).foregroundStyle(Theme.dangerText) }
            SectionTitle(text: "Dernière étape dans Premiere")
            VStack(alignment: .leading, spacing: 6) {
                Muted("1. Ouvre le projet dans Premiere.")
                Muted("2. Enregistre-le dans le dossier de l'épisode (Fichier › Enregistrer sous), puis ferme-le.")
                Muted("3. Clique sur « Finaliser » et choisis ce projet : le multicam et les micros sont réglés.")
            }
            HStack(spacing: 8) {
                Button("Ouvrir dans Premiere") { m.openInPremiere(m.xmlPath) }.buttonStyle(SecondaryButton())
                Button(m.phase == .finalizing ? "Finalisation…" : "Finaliser le projet") { m.finalize() }.buttonStyle(PrimaryButton()).disabled(m.phase == .finalizing)
            }
        }.card()
    }
}

final class PlayerEnd: NSObject, AVAudioPlayerDelegate {
    let done: () -> Void
    init(_ done: @escaping () -> Void) { self.done = done }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { done() }
}
