import SwiftUI
import AppKit
import Supabase

/// Une publication du programme Instagram, en cours d'affichage ou de modification.
struct PostDraft: Identifiable {
    let id = UUID()
    var rowId: Int?
    var handle = "fastsign.app"
    var format = "Carrousel"
    var title = ""
    var status = "Prêt"
    var ref = ""
    var url = ""
    var at: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(86400))
        c.hour = 19
        return Calendar.current.date(from: c) ?? Date()
    }()
}

/// Fiche d'une publication : aperçu (post publié ou fichier du dossier de publication) et modification.
struct PostEditor: View {
    @State var draft: PostDraft
    /// Post Instagram correspondant, s'il est déjà publié (image, j'aime, commentaires).
    let media: [String: Any]?
    let handles: [String]
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var saving = false
    @State private var askDelete = false
    @State private var error: String? = nil
    @State private var localFile: URL? = nil
    @State private var preview: NSImage? = nil

    static let formats = ["Carrousel", "Reel", "Reel d'essai", "Story", "Post"]
    static let statuses = ["À créer", "Prêt", "Programmé", "Publié"]
    static let brands: [String: (String, String)] = ["fastsign.app": ("FastSign", "4C8DFF"), "agora.app.be": ("Agora", "C084FC"),
                                                     "agenceimage.be": ("L'Agence Image", "F472B6"), "minimalist.belgium": ("Minimalist", "8B8D94")]
    /// Nom du dossier de chaque marque dans Bureau › PROJET › Publications Instagram.
    static let folders: [String: String] = ["fastsign.app": "FastSign", "agora.app.be": "Agora", "agenceimage.be": "Agence Image"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.rowId == nil ? "Programme de publication" : (Self.brands[draft.handle]?.0 ?? draft.handle))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text(draft.rowId == nil ? "Nouvelle publication" : draft.title).font(.system(size: 18, weight: .semibold)).lineLimit(2)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(SecondaryButton())
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    previewBlock
                    FormField(label: "Contenu") {
                        TextField("Ce que montre la publication", text: $draft.title, axis: .vertical).lineLimit(2...4).input()
                    }
                    HStack(spacing: 12) {
                        FormField(label: "Compte") {
                            Picker("", selection: $draft.handle) {
                                ForEach(handles, id: \.self) { h in Text("\(Self.brands[h]?.0 ?? h) · @\(h)").tag(h) }
                            }.labelsHidden()
                        }
                        FormField(label: "Format") {
                            Picker("", selection: $draft.format) { ForEach(Self.formats, id: \.self) { Text($0).tag($0) } }.labelsHidden()
                        }
                    }
                    FormField(label: "Date et heure") {
                        DatePicker("", selection: $draft.at).labelsHidden().environment(\.locale, Locale(identifier: "fr_BE"))
                    }
                    FormField(label: "Statut") {
                        Picker("", selection: $draft.status) { ForEach(Self.statuses, id: \.self) { Text($0).tag($0) } }
                            .pickerStyle(.segmented).labelsHidden()
                    }
                    FormField(label: "Fichier", hint: "Numéro du lot et du fichier dans Bureau › PROJET › Publications Instagram.") {
                        TextField("Lot 01 · n°001", text: $draft.ref).input()
                    }
                    FormField(label: "Lien du post") {
                        TextField("https://www.instagram.com/p/…", text: $draft.url).input()
                    }
                    if let error { Text(error).font(.system(size: 12.5)).foregroundStyle(Theme.red) }
                }
                .padding(20)
            }
            Divider()
            HStack {
                if draft.rowId != nil {
                    Button("Supprimer") { askDelete = true }.buttonStyle(SecondaryButton(danger: true))
                }
                Spacer()
                Button("Annuler") { dismiss() }.buttonStyle(SecondaryButton())
                Button(saving ? "Enregistrement…" : (draft.rowId == nil ? "Ajouter au programme" : "Enregistrer")) { Task { await save() } }
                    .buttonStyle(PrimaryButton()).disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 680)
        .background(Theme.bg)
        .task(id: draft.ref + draft.handle) { findLocalFile() }
        .confirmationDialog("Supprimer cette publication du programme ?", isPresented: $askDelete) {
            Button("Supprimer", role: .destructive) { Task { await remove() } }
        } message: { Text(draft.title) }
    }

    // MARK: aperçu

    @ViewBuilder private var previewBlock: some View {
        if let m = media {
            Button { if let s = m["url"] as? String, let u = URL(string: s) { NSWorkspace.shared.open(u) } } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: m["img"] as? String ?? "")) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                        .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Publié sur Instagram").font(.system(size: 14, weight: .semibold))
                        Text("♥ \(Int((m["likes"] as? NSNumber)?.doubleValue ?? 0)) · \(Int((m["comments"] as? NSNumber)?.doubleValue ?? 0)) commentaires")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        Text("Ouvrir le post ↗").font(.system(size: 12.5)).foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                }
                .padding(12).glassCard()
            }
            .buttonStyle(.plain)
        }
        if let f = localFile {
            HStack(spacing: 12) {
                Group {
                    if let preview { Image(nsImage: preview).resizable().scaledToFill() }
                    else { Image(systemName: f.hasDirectoryPath ? "folder" : "film").font(.system(size: 26)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.card2) }
                }
                .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(f.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    HStack(spacing: 8) {
                        Button("Ouvrir") { NSWorkspace.shared.open(f) }.buttonStyle(SecondaryButton())
                        Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([f]) }.buttonStyle(SecondaryButton())
                    }
                }
                Spacer()
            }
            .padding(12).glassCard()
        } else if media == nil, !draft.ref.isEmpty {
            Muted("Fichier introuvable dans Bureau › PROJET › Publications Instagram.", size: 12)
        }
    }

    /// Retrouve le fichier (ou le dossier du carrousel) d'après « Lot 01 · n°001 ».
    private func findLocalFile() {
        localFile = nil; preview = nil
        guard let folder = Self.folders[draft.handle],
              let lot = draft.ref.range(of: #"Lot\s*(\d+)"#, options: .regularExpression).map({ String(draft.ref[$0]).filter(\.isNumber) }),
              let num = draft.ref.range(of: #"n°\s*(\d+)"#, options: .regularExpression).map({ String(draft.ref[$0]).filter(\.isNumber) }) else { return }
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/PROJET/Publications Instagram/\(folder)")
        guard let lots = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil),
              let lotDir = lots.first(where: { $0.lastPathComponent.hasPrefix("Lot \(lot)") }),
              let items = try? fm.contentsOfDirectory(at: lotDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let mine = items.filter { $0.lastPathComponent.hasPrefix("\(num) ·") || $0.lastPathComponent.hasPrefix("\(num) ") }
        let main = mine.first { $0.hasDirectoryPath } ?? mine.first { ["mp4", "mov"].contains($0.pathExtension.lowercased()) } ?? mine.first
        guard let main else { return }
        localFile = main
        // Aperçu : première slide d'un carrousel, miniature JPG d'un reel, ou l'image elle-même
        var img: URL? = nil
        if main.hasDirectoryPath {
            img = (try? fm.contentsOfDirectory(at: main, includingPropertiesForKeys: nil))?
                .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
        } else if ["jpg", "jpeg", "png"].contains(main.pathExtension.lowercased()) {
            img = main
        } else {
            img = mine.first { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
        }
        if let img { preview = NSImage(contentsOf: img) }
    }

    // MARK: enregistrement

    private struct Row: Encodable {
        let handle, format, title, status: String
        let at: String
        let ref: String?
        let post_url: String?
        let updated_at: String
    }

    private func save() async {
        saving = true; defer { saving = false }
        let iso = ISO8601DateFormatter()
        let row = Row(handle: draft.handle, format: draft.format, title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines), status: draft.status,
                      at: iso.string(from: draft.at), ref: draft.ref.isEmpty ? nil : draft.ref, post_url: draft.url.isEmpty ? nil : draft.url,
                      updated_at: iso.string(from: Date()))
        do {
            if let id = draft.rowId { try await supa.from("ig_schedule").update(row).eq("id", value: id).execute() }
            else { try await supa.from("ig_schedule").insert(row).execute() }
            onDone(); dismiss()
        } catch { self.error = "Pas enregistré : \(error.localizedDescription)" }
    }

    private func remove() async {
        guard let id = draft.rowId else { return }
        do {
            try await supa.from("ig_schedule").delete().eq("id", value: id).execute()
            onDone(); dismiss()
        } catch { self.error = "Pas supprimé : \(error.localizedDescription)" }
    }
}
