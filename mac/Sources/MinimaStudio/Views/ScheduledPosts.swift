import SwiftUI
import AppKit
import Supabase

/// Une ligne du programme de publication (table ig_schedule).
struct SchedPost: Codable, Identifiable, Hashable {
    let id: Int
    let handle: String
    let at: String
    let format: String
    let title: String
    let status: String
    let ref: String?
    let post_url: String?

    var date: Date { DateFmt.parse(at) ?? .distantFuture }

    var draft: PostDraft {
        PostDraft(rowId: id, handle: handle, format: format, title: title, status: status,
                  ref: ref ?? "", url: post_url ?? "", at: date)
    }
}

/// Miniatures des publications, lues dans Bureau › PROJET › Publications Instagram.
/// Lecture hors du thread principal, résultat gardé en mémoire.
enum PostThumbs {
    private static let cache = NSCache<NSString, NSImage>()
    private static let none = NSImage()
    /// Dossier de chaque marque dans Bureau › PROJET › Publications Instagram (comme PostEditor.folders).
    private static let folders: [String: String] = ["fastsign.app": "FastSign", "agora.app.be": "Agora", "agenceimage.be": "Agence Image"]

    static func image(handle: String, ref: String?) async -> NSImage? {
        guard let ref, !ref.isEmpty else { return nil }
        let key = "\(handle)|\(ref)" as NSString
        if let hit = cache.object(forKey: key) { return hit === none ? nil : hit }
        let cg = await Task.detached(priority: .utility) { load(handle: handle, ref: ref) }.value
        let img = cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        cache.setObject(img ?? none, forKey: key)
        return img
    }

    private static func load(handle: String, ref: String) -> CGImage? {
        guard let folder = folders[handle],
              let lot = ref.range(of: #"Lot\s*(\d+)"#, options: .regularExpression).map({ String(ref[$0]).filter(\.isNumber) }),
              let num = ref.range(of: #"n°\s*(\d+)"#, options: .regularExpression).map({ String(ref[$0]).filter(\.isNumber) }) else { return nil }
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/PROJET/Publications Instagram/\(folder)")
        guard let lots = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil),
              let lotDir = lots.first(where: { $0.lastPathComponent.hasPrefix("Lot \(lot)") }),
              let items = try? fm.contentsOfDirectory(at: lotDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        let mine = items.filter { $0.lastPathComponent.hasPrefix("\(num) ·") || $0.lastPathComponent.hasPrefix("\(num) ") }
        let main = mine.first { $0.hasDirectoryPath } ?? mine.first { ["mp4", "mov"].contains($0.pathExtension.lowercased()) } ?? mine.first
        guard let main else { return nil }
        let isImg: (URL) -> Bool = { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
        var img: URL?
        if main.hasDirectoryPath {
            img = (try? fm.contentsOfDirectory(at: main, includingPropertiesForKeys: nil))?.filter(isImg).sorted { $0.lastPathComponent < $1.lastPathComponent }.first
        } else if isImg(main) {
            img = main
        } else {
            img = mine.first(where: isImg)
        }
        guard let img, let src = CGImageSourceCreateWithURL(img as CFURL, nil) else { return nil }
        // Miniature réduite : on ne charge jamais l'image en pleine taille.
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 480]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

/// Aperçu des prochaines publications : miniature, compte, format, jour et heure, statut.
struct ScheduledPostsCard: View {
    /// Accueil : version compacte avec un lien vers Marques.
    var compact = false
    @EnvironmentObject var presenter: Presenter
    @State private var rows: [SchedPost] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var editing: PostDraft?

    private static let handles = ["fastsign.app", "agora.app.be", "agenceimage.be", "minimalist.belgium"]

    private var late: [SchedPost] {
        let start = Calendar.current.startOfDay(for: Date())
        return rows.filter { $0.format != "Story" && $0.status != "Publié" && $0.date < start }
    }

    private var upcoming: [SchedPost] {
        let start = Calendar.current.startOfDay(for: Date())
        return rows.filter { $0.date >= start && $0.status != "Publié" }.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Prochaines publications").font(.system(size: 15, weight: .semibold))
                Spacer()
                if loaded, !late.isEmpty {
                    Text("\(late.count) pas encore vu\(late.count > 1 ? "s" : "") en ligne")
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.amber)
                        .padding(.horizontal, 9).padding(.vertical, 3).background(Theme.amber.opacity(0.14), in: Capsule())
                }
                if compact {
                    Button("Tout le programme") { presenter.go(.apps) }.buttonStyle(.plain)
                        .font(.system(size: 12.5)).foregroundStyle(Color.accentColor)
                }
            }
            if !loaded {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Muted("Chargement du programme…") }
            } else if failed {
                Muted("Le programme n'a pas pu être chargé.")
            } else if upcoming.isEmpty && late.isEmpty {
                Muted("Rien de programmé pour l'instant.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(late + upcoming.prefix(compact ? 8 : 16)) { p in
                            PostTile(post: p, isLate: late.contains(p)) { editing = p.draft }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(18).glassCard()
        .task { await load() }
        .sheet(item: $editing) { d in
            PostEditor(draft: d, media: nil, handles: Self.handles) { Task { await load() } }
        }
    }

    private func load() async {
        let start = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let end = Calendar.current.date(byAdding: .day, value: 28, to: Date()) ?? Date()
        let iso = ISO8601DateFormatter()
        do {
            let list: [SchedPost] = try await supa.from("ig_schedule")
                .select("id,handle,at,format,title,status,ref,post_url")
                .gte("at", value: iso.string(from: start)).lte("at", value: iso.string(from: end))
                .order("at").execute().value
            rows = list; failed = false
        } catch { failed = rows.isEmpty }
        loaded = true
    }
}

private struct PostTile: View {
    let post: SchedPost
    let isLate: Bool
    let open: () -> Void
    @State private var image: NSImage?
    @State private var hover = false

    private var brand: (String, String) { PostEditor.brands[post.handle] ?? (post.handle, "8B8D94") }
    private var statusColor: Color {
        switch post.status {
        case "Prêt": return Theme.green
        case "Programmé": return Color(hex: "4C8DFF")
        case "À créer": return Theme.amber
        default: return Theme.muted
        }
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    Group {
                        if let image { Image(nsImage: image).resizable().scaledToFill() }
                        else {
                            ZStack {
                                LinearGradient(colors: [Color(hex: brand.1).opacity(0.35), Color(hex: brand.1).opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                Image(systemName: post.format.contains("Reel") ? "play.rectangle" : post.format == "Story" ? "circle.dashed" : "square.stack")
                                    .font(.system(size: 26, weight: .light)).foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .frame(width: 148, height: 185).clipped()
                    Text(post.format).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(.black.opacity(0.55), in: Capsule()).padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isLate ? Theme.amber.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: brand.1)).frame(width: 7, height: 7)
                        Text(brand.0).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    }
                    Text(post.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(Locale(identifier: "fr_BE"))))
                        .font(.system(size: 11.5)).foregroundStyle(isLate ? Theme.amber : Theme.muted).lineLimit(1)
                    Text(post.title).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(post.status).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(statusColor)
                        .padding(.horizontal, 8).padding(.vertical, 2.5).background(statusColor.opacity(0.15), in: Capsule())
                        .padding(.top, 2)
                }
                .frame(width: 148, alignment: .leading)
            }
            .scaleEffect(hover ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help("Afficher et modifier")
        .task(id: post.ref ?? "") { image = await PostThumbs.image(handle: post.handle, ref: post.ref) }
    }
}
