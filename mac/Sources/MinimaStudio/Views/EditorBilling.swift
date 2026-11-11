import SwiftUI
import AppKit

// MARK: - Facturation des monteurs (fin de mois)
// Une mission compte dans la facture du mois où le monteur la livre (sauf mois choisi par l'admin).
// « Client payé » (le client a payé Gaston) et « monteur payé » (Gaston a payé le monteur) sont deux choses distinctes.

private func monthName(_ d: Date) -> String { BillMonth.label(d).lowercased() }
private func monthOnly(_ d: Date) -> String { d.formatted(.dateTime.month(.wide).locale(Locale(identifier: "fr_BE"))) }
private func isCurrentOrFuture(_ d: Date) -> Bool {
    let now = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    return d >= now
}
private func money(_ v: Double) -> String { Money.eur((v * 100).rounded() / 100) }
/// « d'octobre », « de mai »
private func deMois(_ d: Date) -> String { let n = monthOnly(d); return "aeiouyéh".contains(n.prefix(1).lowercased()) ? "d'\(n)" : "de \(n)" }

enum StatementKind { case paid, due, complement, current, empty, sent }

extension DataStore {
    /// État du relevé d'un monteur pour un mois.
    func statementKind(user: String, month: Date) -> (kind: StatementKind, rest: Double) {
        let st = statement(user: user, month: month)
        let rest = max(0, ((st.total - (st.payment?.amount ?? 0)) * 100).rounded() / 100)
        if let _ = st.payment { return (rest > 0.5 ? .complement : .paid, rest) }
        if st.total == 0 { return (.empty, 0) }
        if invoice(user: user, month: month) != nil { return (.sent, st.total) }
        return (isCurrentOrFuture(month) ? .current : .due, st.total)
    }

    /// Mois terminés pas encore payés (jusqu'à `back` mois en arrière).
    func unpaidMonths(user: String, back: Int = 12) -> [(month: Date, amount: Double)] {
        let cal = Calendar.current
        let now = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        return (1...back).compactMap { i in
            guard let mo = cal.date(byAdding: .month, value: -i, to: now) else { return nil }
            let k = statementKind(user: user, month: mo)
            return (k.kind == .due || k.kind == .complement || k.kind == .sent) ? (mo, k.rest) : nil
        }
    }

    func statementText(user: String, month: Date) -> String {
        let st = statement(user: user, month: month)
        let name = profile(user)?.displayName ?? ""
        let df = Date.FormatStyle().day(.twoDigits).month(.twoDigits).locale(Locale(identifier: "fr_BE"))
        func n2(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }
        var lines = ["Prestations de montage · \(name) · \(monthName(month)) · à facturer à Minimalist Belgium (HTVA)", "",
                     ["Date", "Client", "Mission", "Part", "Montant HTVA (€)"].joined(separator: "\t")]
        for r in st.rows {
            let c = client(r.mission.client_id)?.name ?? ""
            let day = r.mission.missionDay.map { $0.formatted(df) } ?? ""
            lines.append([day, c, r.mission.title, "\(Int(r.percent.rounded())) % de \(n2(r.mission.editor_budget ?? 0)) €", n2(r.amount)].joined(separator: "\t"))
        }
        lines.append(["", "", "", "Total HTVA", n2(st.total)].joined(separator: "\t"))
        if let p = st.payment, st.total - p.amount > 0.5 {
            lines.append(["", "", "", "Déjà payé", "-" + n2(p.amount)].joined(separator: "\t"))
            lines.append(["", "", "", "Reste à facturer HTVA", n2(st.total - p.amount)].joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }
}

/// Relevé du mois : ce que le monteur doit facturer (vue monteur) ou ce que l'admin doit lui payer.
struct EditorStatementCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    let user: String
    let month: Date
    var admin = false
    var showRows = true
    @State private var confirmPay = false
    @State private var confirmUndo = false
    @State private var busy = false
    @State private var confirmSent = false

    private var isCurrentMonth: Bool { Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month) }
    private var isFuture: Bool { month > (Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()) && !isCurrentMonth }

    var body: some View {
        let st = data.statement(user: user, month: month)
        let k = data.statementKind(user: user, month: month)
        let sent = data.invoice(user: user, month: month)
        let pending = isCurrentMonth ? data.pendingRows(user: user) : []
        let canSend = !admin && st.total > 0 && st.payment == nil && !isFuture
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if admin, let p = data.profile(user) {
                    AvatarView(profile: p, size: 26).clipShape(Circle())
                    Text(p.displayName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                } else {
                    Text("Ma facture · \(monthName(month))").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                }
                Spacer(minLength: 8)
                pill(k.kind)
            }
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Muted(bigLabel(k.kind), size: 12)
                    Text(money(k.kind == .paid ? (st.payment?.amount ?? 0) : k.kind == .complement ? k.rest : st.total))
                        .font(.system(size: 30, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(line(k.kind, st.payment, sent)).font(.system(size: 13)).multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    Muted("\(st.rows.count) mission\(st.rows.count > 1 ? "s" : "")", size: 12)
                }
            }
            if showRows && !st.rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(st.rows) { r in
                        Rectangle().fill(Theme.line).frame(height: 1)
                        row(r)
                    }
                    Rectangle().fill(Theme.line).frame(height: 1)
                    HStack {
                        Text("Total HTVA").font(.system(size: 13.5, weight: .semibold))
                        Spacer()
                        Text(money(st.total)).font(.system(size: 14, weight: .semibold, design: .monospaced))
                    }
                    .padding(.vertical, 10)
                    if k.kind == .complement, let p = st.payment {
                        HStack {
                            Muted("Déjà payé", size: 13)
                            Spacer()
                            Text("−" + money(p.amount)).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.muted)
                        }
                        HStack {
                            Text(admin ? "Reste à payer HTVA" : "Reste à facturer HTVA").font(.system(size: 13.5, weight: .semibold))
                            Spacer()
                            Text(money(k.rest)).font(.system(size: 14, weight: .semibold, design: .monospaced))
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            if !pending.isEmpty {
                VStack(spacing: 0) {
                    Muted("En cours de montage · pas encore dans la facture", size: 11.5).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
                    ForEach(pending) { r in
                        Rectangle().fill(Theme.line).frame(height: 1)
                        HStack(spacing: 10) {
                            Text(r.mission.deadlineDate.map { $0.formatted(Date.FormatStyle().day(.twoDigits).month(.twoDigits)) } ?? "")
                                .font(.system(size: 12, design: .monospaced)).frame(width: 42, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.mission.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text("\(Int(r.percent.rounded())) % de \(Money.eur(r.mission.editor_budget ?? 0)) · \(MissionStatus.label(r.mission.status).lowercased())\(r.estimated ? " · estimation" : "")")
                                    .font(.system(size: 11.5)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("≈ " + Money.eur(r.amount.rounded())).font(.system(size: 13, design: .monospaced)).lineLimit(1).fixedSize()
                        }
                        .padding(.vertical, 7)
                    }
                    Rectangle().fill(Theme.line).frame(height: 1)
                    HStack {
                        Text(admin ? "S'il livre tout ce mois-ci" : "Si tu livres tout ce mois-ci").font(.system(size: 13))
                        Spacer()
                        Text("≈ " + Money.eur((st.total + pending.map(\.amount).reduce(0, +)).rounded())).font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    }
                    .padding(.vertical, 8)
                }
                .foregroundStyle(Theme.muted)
                .opacity(0.75)
            }
            if !st.rows.isEmpty || (admin && st.total > 0) {
                HStack(spacing: 8) {
                    if canSend && sent == nil {
                        Button { confirmSent = true } label: { Label("J'ai envoyé ma facture", systemImage: "checkmark") }
                            .buttonStyle(SecondaryButton()).disabled(busy)
                    }
                    if !admin, st.total > 0, k.kind != .paid, sent == nil, let link = data.invoiceLink, let url = URL(string: link) {
                        Button { NSWorkspace.shared.open(url) } label: { Label("Faire ma facture sur Smart", systemImage: "arrow.up.right.square") }
                            .buttonStyle(PrimaryButton())
                    }
                    if !st.rows.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(data.statementText(user: user, month: month), forType: .string)
                            app.showToast("Détail copié : colle-le dans ta facture")
                        } label: { Label("Copier le détail", systemImage: "doc.on.doc") }
                        .buttonStyle(SecondaryButton())
                    }
                    if admin && st.total > 0 && k.kind != .paid {
                        Button { confirmPay = true } label: { Text(k.kind == .complement ? "Payer le complément" : "Marquer payé") }
                            .buttonStyle(PrimaryButton()).disabled(busy)
                    }
                    if canSend && sent != nil {
                        Spacer(minLength: 4)
                        Button("Pas encore envoyée") { run { try await data.unmarkInvoiceSent(user: user, month: month) } }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted).underline().disabled(busy)
                    }
                    if admin && st.payment != nil {
                        Spacer(minLength: 4)
                        Button("Annuler le paiement") { confirmUndo = true }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted).underline().disabled(busy)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: k.kind == .due ? Theme.amber.opacity(0.06) : nil)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(k.kind == .due ? Theme.amber.opacity(0.4) : k.kind == .paid ? Theme.green.opacity(0.3) : .clear))
        .confirmationDialog("Marquer \(data.profile(user)?.firstName ?? "") payé pour \(monthName(month)) ?", isPresented: $confirmPay) {
            Button(st.payment == nil ? "Marquer payé \(money(st.total))" : "Enregistrer \(money(st.total)) payés au total") { run { try await data.markEditorPaid(user: user, month: month, amount: st.total) } }
        } message: { Text(st.payment.map { "Déjà payé \(money($0.amount)), reste \(money(k.rest))." } ?? "Montant de son relevé : \(money(st.total)) HTVA.") }
        .confirmationDialog("Facture \(monthOnly(month)) envoyée ?", isPresented: $confirmSent) {
            Button("Oui, envoyée") { run { try await data.markInvoiceSent(user: user, month: month, amount: st.total) } }
        } message: { Text("Gaston sera prévenu que tu as envoyé ta facture de \(money(st.total)) HTVA.") }
        .confirmationDialog("Annuler ce paiement ?", isPresented: $confirmUndo) {
            Button("Annuler le paiement", role: .destructive) { run { try await data.unmarkEditorPaid(user: user, month: month) } }
        } message: { Text("\(data.profile(user)?.firstName ?? "") repassera en « à payer » pour \(monthName(month)).") }
    }

    private func run(_ f: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await f(); app.showToast("C'est noté") } catch { app.showToast("Impossible : \(error.localizedDescription)") }
            busy = false
        }
    }

    private func row(_ r: DataStore.StatementRow) -> some View {
        let c = data.client(r.mission.client_id)
        let day = r.mission.missionDay.map { $0.formatted(Date.FormatStyle().day(.twoDigits).month(.twoDigits)) } ?? ""
        return Button { presenter.open(.existing(r.mission.id)) } label: {
            HStack(spacing: 10) {
                Text(day).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted).frame(width: 42, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.mission.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("\(Int(r.percent.rounded())) % de \(Money.eur(r.mission.editor_budget ?? 0)) · \(c?.name ?? "Sans client")\(note(r))")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(money(r.amount)).font(.system(size: 13, weight: .semibold, design: .monospaced)).lineLimit(1).fixedSize()
            }
            .padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverRow(radius: 8)
    }

    private func note(_ r: DataStore.StatementRow) -> String {
        var n: [String] = []
        if r.mission.bill_month != nil, let d = r.mission.missionDay, !Calendar.current.isDate(d, equalTo: month, toGranularity: .month) { n.append("reportée sur ce mois par Gaston") }
        if r.amount <= 0 { n.append(admin ? "0 % : aucun temps enregistré pour lui" : "0 % : aucun temps enregistré pour toi, préviens Gaston") }
        if admin && !r.mission.clientPaid { n.append("client pas encore payé") }
        return n.isEmpty ? "" : " · " + n.joined(separator: " · ")
    }

    private func pill(_ k: StatementKind) -> some View {
        let (t, c): (String, Color) = {
            switch k {
            case .paid: return ("Payé", Theme.green)
            case .due: return (admin ? "À payer" : "À facturer", Theme.amber)
            case .complement: return ("Complément", Theme.amber)
            case .current: return ("En cours", Theme.muted)
            case .empty: return ("–", Theme.muted)
            case .sent: return (admin ? "Facture reçue" : "Envoyée", Theme.blue)
            }
        }()
        return Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(c)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(c.opacity(0.15), in: Capsule())
    }

    private func bigLabel(_ k: StatementKind) -> String {
        switch k {
        case .paid: return "Payé"
        case .complement: return "Reste à payer"
        case .sent: return admin ? "À lui payer" : "Facturé HTVA"
        default: return admin ? "À lui payer" : "Montant à facturer HTVA"
        }
    }

    private func line(_ k: StatementKind, _ p: EditorPayment?, _ inv: EditorInvoice?) -> String {
        switch k {
        case .sent:
            let d = inv.flatMap { DateFmt.parse($0.sent_at) }?.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_BE"))) ?? ""
            return admin ? "Facture reçue le \(d) (\(money(inv?.amount ?? 0))) · à payer" : "Facture envoyée le \(d) · en attente de paiement"
        case .paid:
            let d = p.flatMap { DateFmt.parse($0.paid_at) }?.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_BE"))) ?? ""
            return admin ? "Payé le \(d)" : "Minimalist t'a payé le \(d)"
        case .complement: return "Déjà payé \(money(p?.amount ?? 0)) · le relevé a changé depuis le paiement"
        case .current: return admin ? "Mois en cours : le total peut encore bouger" : "Mois en cours : tu factureras début \(monthOnly(Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month))"
        case .due: return admin ? "À payer" : "À facturer à Minimalist Belgium"
        case .empty: return "Aucune mission à facturer ce mois-ci"
        }
    }
}

/// Trésorerie : payer les monteurs avant d'avoir été payé par les clients ?
struct CashCard: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    let month: Date

    var body: some View {
        let cal = Calendar.current
        let ms = data.missions.filter { $0.status != "requested" && ($0.billMonth.map { cal.isDate($0, equalTo: month, toGranularity: .month) } ?? false) }
        let people = data.payees
        let dues = ms.map { m in (m, people.map { data.share(of: m, user: $0.id).amount }.reduce(0, +)) }.filter { $0.1 > 0 }
        let toPay = dues.map(\.1).reduce(0, +)
        let paid = people.compactMap { data.statement(user: $0.id, month: month).payment?.amount }.reduce(0, +)
        let cashIn = ms.filter(\.clientPaid).compactMap { data.finances[$0.id]?.client_price }.reduce(0, +)
        let waiting = ms.filter { !$0.clientPaid }.compactMap { data.finances[$0.id]?.client_price }.reduce(0, +)
        let late = dues.filter { !$0.0.clientPaid }
        let balance = cashIn - toPay
        if toPay > 0 || cashIn > 0 {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Trésorerie · \(monthName(month))").font(.system(size: 15, weight: .semibold))
                    Muted("Paiement des monteurs comparé à ce que les clients t'ont déjà payé", size: 12)
                }
                HStack(alignment: .top, spacing: 12) {
                    figure("Encaissé des clients", Money.eur(cashIn.rounded()), Theme.green)
                    figure("Pour les monteurs", Money.eur(toPay.rounded()), Theme.text, foot: paid > 0 ? "dont \(Money.eur(paid.rounded())) déjà versés" : "rien versé pour l'instant")
                    figure("Encaissé moins monteurs", (balance >= 0 ? "+" : "−") + Money.eur(abs(balance).rounded()), balance >= 0 ? Theme.green : Theme.red)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: balance >= 0 ? "checkmark.circle" : "exclamationmark.triangle").foregroundStyle(balance >= 0 ? Theme.green : Theme.red)
                    Text(verdict(balance: balance, left: max(0, toPay - paid), toPay: toPay, cashIn: cashIn, late: late.count, waiting: waiting))
                        .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                .background((balance >= 0 ? Theme.green : Theme.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !late.isEmpty {
                    Muted("Pas encore payées par le client", size: 12)
                    VStack(spacing: 0) {
                        ForEach(late.prefix(6), id: \.0.id) { m, due in
                            HStack(spacing: 10) {
                                ClientDot(color: data.client(m.client_id)?.color)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(m.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Muted("\(data.client(m.client_id)?.name ?? "Sans client") · \(data.finances[m.id]?.client_price.map { "client \(Money.eur($0))" } ?? "prix client à renseigner") · monteur \(Money.eur(due.rounded()))", size: 11.5).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Ouvrir") { presenter.open(.existing(m.id)) }.buttonStyle(SecondaryButton())
                            }
                            .padding(.vertical, 7)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func verdict(balance: Double, left: Double, toPay: Double, cashIn: Double, late: Int, waiting: Double) -> String {
        let miss = "\(late) mission\(late > 1 ? "s" : "") pas encore payée\(late > 1 ? "s" : "") par le client (\(Money.eur(waiting.rounded())) attendus)"
        if balance >= 0 { return "Les clients ont déjà payé de quoi couvrir les monteurs : il te reste \(Money.eur(balance.rounded()))" + (left > 0.5 ? ", et \(Money.eur(left.rounded())) à verser." : ".") }
        if left <= 0.5 { return "Tu as avancé \(Money.eur((-balance).rounded())) de ta poche : \(miss)." }
        return "Il te reste \(Money.eur(left.rounded())) à verser. Si tu payes maintenant, tu avances \(Money.eur(max(0, toPay - cashIn).rounded())) de ta poche : \(miss)."
    }

    private func figure(_ l: String, _ v: String, _ c: Color, foot: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Muted(l, size: 12).lineLimit(1)
            Text(v).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
            if let foot { Muted(foot, size: 11.5).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Section admin de la page Finances : trésorerie et relevé de chaque monteur.
struct EditorPayoutsSection: View {
    @EnvironmentObject var data: DataStore
    let month: Date

    var body: some View {
        let people = data.payees.filter { data.statement(user: $0.id, month: month).total > 0 || data.statement(user: $0.id, month: month).payment != nil }
        VStack(alignment: .leading, spacing: 14) {
            CashCard(month: month)
            SectionTitle(text: "Paiement des monteurs · \(monthName(month))", trailing: "Ce que chacun doit te facturer")
            if people.isEmpty {
                EmptyHint(text: "Aucune mission à payer aux monteurs pour \(monthName(month)).").card()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(people) { p in EditorStatementCard(user: p.id, month: month, admin: true) }
                }
            }
        }
    }
}

/// Rappel de fin de mois sur l'accueil du monteur.
struct InvoiceNudge: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore

    var body: some View {
        if let me = app.profile?.id {
            let list = data.unpaidMonths(user: me, back: 12).filter { data.invoice(user: me, month: $0.month) == nil }
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    let first = list[0]
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text").foregroundStyle(Theme.amber)
                        Text("Ta facture \(deMois(first.month)) : ").font(.system(size: 13.5))
                            + Text(money(first.amount)).font(.system(size: 13.5, weight: .semibold))
                            + Text(" HTVA à facturer à Minimalist Belgium. Le détail est dans Finances.").font(.system(size: 13.5))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if list.count > 1 {
                        Muted("+ \(list.count - 1) autre\(list.count > 2 ? "s" : "") mois pas encore réglé\(list.count > 2 ? "s" : "") : \(money(list.dropFirst().map(\.amount).reduce(0, +)))", size: 12)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.amber.opacity(0.35)))
            }
        }
    }
}
