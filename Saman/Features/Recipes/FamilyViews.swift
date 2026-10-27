import SwiftUI
import Combine
import SwiftData

// MARK: - Copy

enum FamilyCopy {
    static let shelfTitle = "Families"
    static let emptyTitle = "No families yet"
    static let emptyBody = "Start a family cookbook and invite the people who cook with you. Only members can see it."
    static let signInBody = "Sign in to start a family cookbook or join one with a code."
    static let createAction = "Start a family"
    static let joinAction = "Join with a code"
    static let createTitle = "Name your family"
    static let createPlaceholder = "Khan family"
    static let inviteAction = "Invite"
    static let membersAction = "Members"
    static let addToFamilyAction = "Add to family"
    static let addToFamilyTitle = "Add to a family"
    static let addToFamilyBody = "Members can read the ingredients and steps. Your recording and transcript stay in your book."
    static let saveCopyAction = "Save a copy"
    static let savedCopy = "Saved to your book. It stays yours, even if you leave."
    static let recipesEmpty = "No recipes here yet. Open any of your recipes and tap Add to family."
    static let leaveAction = "Leave family"
    static let leaveMessage = "You'll lose access to this family. Recipes you added stay for everyone else, and your saved copies stay in your book."
    static let removeMessage = "They lose access right away. Recipes they added stay in the family."
    static let deleteAction = "Delete family"
    static let deleteMessage = "This removes the family and its notes for everyone. Members keep any copies they saved."
    static let transferAction = "Make owner"
    static let joinTitle = "Join a family"
    static let joinBody = "Enter the 8-character code someone in your family sent you. Joining is free."
    static let notesTitle = "Notes"
    static let notePlaceholder = "Add a note, like how Nani adjusts the chilli"
    static let paywallContext = "Starting a family cookbook needs Samaan Pro. Joining one is free."
    static let yourNameTitle = "Your name"
    static let yourNamePlaceholder = "Name"
    static let yourNameFooter = "Members of your families see this name. Leave it blank to use the start of your email."
    static let editNameAction = "Edit your name"
    static let unknownAuthor = "A former member"

    static var all: [String] {
        [shelfTitle, emptyTitle, emptyBody, signInBody, createAction, joinAction, createTitle,
         inviteAction, membersAction, addToFamilyAction, addToFamilyTitle, addToFamilyBody,
         saveCopyAction, savedCopy, recipesEmpty, leaveAction, leaveMessage, removeMessage,
         deleteAction, deleteMessage, transferAction, joinTitle, joinBody, notesTitle,
         notePlaceholder, paywallContext, yourNameTitle, yourNamePlaceholder, yourNameFooter,
         editNameAction, unknownAuthor]
    }
}

// MARK: - Your name (shown to members)

/// Name field shared by the create, join and members screens.
struct FamilyNameSection: View {
    @Binding var name: String

    var body: some View {
        Section(header: Text(FamilyCopy.yourNameTitle), footer: Text(FamilyCopy.yourNameFooter)) {
            TextField(FamilyCopy.yourNamePlaceholder, text: $name)
                .textInputAutocapitalization(.words)
                .textContentType(.name)
                .accessibilityIdentifier("families.yourName")
            if name.count > FamilyDisplayName.maxLength {
                Text(FamilyError.nameTooLong.localizedDescription).font(.caption).foregroundStyle(.red)
            }
        }
    }

    static func isValid(_ name: String) -> Bool {
        FamilyDisplayName.normalized(name).count <= FamilyDisplayName.maxLength
    }
}

/// Loads the saved name once, and saves it only when it changed.
@MainActor
final class FamilyNameModel: ObservableObject {
    @Published var name = ""
    private var saved: String?
    private var loaded = false

    func load() async {
        guard !loaded else { return }
        loaded = true
        saved = await FamilyService.shared.myDisplayName()
        if name.isEmpty { name = saved ?? "" }
    }

    func saveIfChanged() async throws {
        let normalized = FamilyDisplayName.normalized(name)
        guard normalized != (saved ?? "") else { return }
        try await FamilyService.shared.setDisplayName(normalized)
        saved = normalized.isEmpty ? nil : normalized
        name = normalized
    }
}

/// Edit your name from family settings.
struct EditFamilyNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    @StateObject private var model = FamilyNameModel()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                FamilyNameSection(name: $model.name)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(FamilyCopy.yourNameTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || !FamilyNameSection.isValid(model.name))
                }
            }
            .task { await model.load() }
        }
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do { try await model.saveIfChanged(); onSaved(); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - Families list (Recipes tab shelf)

struct FamiliesView: View {
    @Environment(\.appEnv) private var appEnv
    @State private var families: [Family] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showPaywall = false

    var body: some View {
        Group {
            if !appEnv.auth.isSignedIn {
                prompt(title: FamilyCopy.shelfTitle, body: FamilyCopy.signInBody) {
                    Button("Sign in") { appEnv.requireAccount() }
                        .buttonStyle(SamaanPrimaryButtonStyle())
                }
            } else if isLoading && families.isEmpty {
                ProgressView().tint(Color.brandSaag)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if families.isEmpty {
                prompt(title: FamilyCopy.emptyTitle, body: errorMessage ?? FamilyCopy.emptyBody) { actions }
            } else {
                list
            }
        }
        .background(Color.surfaceDoodh)
        .task(id: appEnv.auth.isSignedIn) { await reload() }
        .onChange(of: appEnv.pendingFamilyJoin) { _, value in
            presentPendingJoin(value)
        }
        .onChange(of: appEnv.auth.isSignedIn) { _, signedIn in
            if signedIn { presentPendingJoin(appEnv.pendingFamilyJoin) }
        }
        .sheet(isPresented: $showCreate) {
            CreateFamilySheet { _ in Task { await reload() } }
        }
        .sheet(isPresented: $showJoin, onDismiss: {
            // Only the signed-in join sheet clears the token. A signed-out
            // invite keeps pendingFamilyJoin until AuthView finishes.
            if appEnv.auth.isSignedIn { appEnv.pendingFamilyJoin = nil }
        }) {
            JoinFamilySheet(initialValue: appEnv.pendingFamilyJoin) { _ in Task { await reload() } }
        }
        .sheet(isPresented: $showPaywall) { SamaanPaywallView(trigger: .createFamily) }
        .fullScreenCover(isPresented: Binding(
            get: { appEnv.isAuthPresented },
            set: { appEnv.isAuthPresented = $0 }
        )) {
            AuthView()
        }
        .onAppear { presentPendingJoin(appEnv.pendingFamilyJoin) }
        .heycatchScreen("Families")
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(FamilyCopy.createAction) { startCreate() }
                .buttonStyle(SamaanPrimaryButtonStyle())
                .accessibilityIdentifier("families.create")
            Button(FamilyCopy.joinAction) { showJoin = true }
                .buttonStyle(SamaanSecondaryButtonStyle())
                .accessibilityIdentifier("families.join")
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(families) { family in
                    NavigationLink(destination: FamilyDetailView(family: family, onChange: { Task { await reload() } })) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(family.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.inkKohl)
                                Text(family.ownerId.uuidString == appEnv.auth.currentUserID ? "You started this family" : "Member")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.inkKohlSoft)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.inkKohlSoft)
                        }
                        .padding(14)
                        .samaanCard()
                    }
                    .buttonStyle(.plain)
                }
                actions.padding(.top, 12)
            }
            .padding(.horizontal, Samaan.Space.md)
            .padding(.vertical, 8)
        }
        .refreshable { await reload() }
    }

    private func prompt<Actions: View>(title: String, body: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(title).font(.cormorant(size: 28)).foregroundStyle(Color.inkKohl)
            Text(body)
                .font(.system(size: 14)).foregroundStyle(Color.inkKohlSoft)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            actions().padding(.horizontal, Samaan.Space.md)
            Spacer()
        }
    }

    /// Pro or grandfathered can start a family. Everyone else sees the paywall.
    private func startCreate() {
        Task { @MainActor in
            if appEnv.purchases.isPro {
                showCreate = true
            } else if await FamilyService.shared.serverCanCreateFamily() {
                showCreate = true
            } else {
                showPaywall = true
            }
        }
    }

    /// Signed-out invite links keep the token and open AuthView. The join
    /// sheet waits until there is a session so dismiss cannot drop the link.
    private func presentPendingJoin(_ value: String?) {
        guard value != nil else { return }
        if appEnv.auth.isSignedIn {
            showJoin = true
        } else {
            appEnv.requireAccount()
        }
    }

    private func reload() async {
        guard appEnv.auth.isSignedIn else { families = []; return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { families = try await FamilyService.shared.myFamilies() }
        catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - Create

struct CreateFamilySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var appEnv
    let onCreated: (Family) -> Void
    @State private var name = ""
    @StateObject private var nameModel = FamilyNameModel()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField(FamilyCopy.createPlaceholder, text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("families.create.name")
                FamilyNameSection(name: $nameModel.name)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .task { await nameModel.load() }
            .navigationTitle(FamilyCopy.createTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { save() }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty || name.count > 60
                                  || !FamilyNameSection.isValid(nameModel.name))
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await nameModel.saveIfChanged()
                let family = try await FamilyService.shared.createFamily(name: name, isProOnDevice: appEnv.purchases.isPro)
                onCreated(family)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Join (code or link)

struct JoinFamilySheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialValue: String?
    let onJoined: (UUID) -> Void
    @State private var code = ""
    @StateObject private var nameModel = FamilyNameModel()
    @State private var preview: FamilyInvitePreview?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    Section {
                        Text(preview.name).font(.headline)
                        Text("Started by \(preview.ownerLabel) · \(preview.memberCount) members")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !preview.alreadyMember { FamilyNameSection(name: $nameModel.name) }
                    Button(preview.alreadyMember ? "Open family" : "Join \(preview.name)") { join() }
                        .disabled(isWorking || !FamilyNameSection.isValid(nameModel.name))
                        .accessibilityIdentifier("families.join.confirm")
                } else {
                    Section(footer: Text(FamilyCopy.joinBody)) {
                        TextField("Code", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("families.join.code")
                    }
                    Button("Continue") { lookUp(FamilyInviteLink.normalizedCode(code)) }
                        .disabled(isWorking || FamilyInviteLink.normalizedCode(code).count != 8)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(FamilyCopy.joinTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                await nameModel.load()
                if let initialValue, preview == nil { lookUp(initialValue) }
            }
        }
    }

    private var joinValue: String { initialValue ?? FamilyInviteLink.normalizedCode(code) }

    private func lookUp(_ value: String) {
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do { preview = try await FamilyService.shared.preview(codeOrToken: value) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func join() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                // Same order as create: write the name first so redeem can
                // stamp the member row. A failed save must not look like success.
                if preview?.alreadyMember == false { try await nameModel.saveIfChanged() }
                let id = try await FamilyService.shared.join(codeOrToken: joinValue)
                onJoined(id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Family page

struct FamilyDetailView: View {
    @Environment(\.appEnv) private var appEnv
    @Environment(\.dismiss) private var dismiss
    let family: Family
    let onChange: () -> Void
    @State private var recipes: [FamilyRecipe] = []
    @State private var invite: FamilyInvite?
    @State private var showMembers = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(family.name).font(.cormorant(size: 30)).foregroundStyle(Color.inkKohl)
                HStack(spacing: 10) {
                    Button(FamilyCopy.inviteAction) { makeInvite() }
                        .buttonStyle(SamaanPrimaryButtonStyle())
                        .accessibilityIdentifier("family.invite")
                    Button(FamilyCopy.membersAction) { showMembers = true }
                        .buttonStyle(SamaanSecondaryButtonStyle())
                        .accessibilityIdentifier("family.members")
                }
                if let errorMessage {
                    Text(errorMessage).font(.system(size: 13)).foregroundStyle(.red)
                }
                if recipes.isEmpty {
                    Text(FamilyCopy.recipesEmpty)
                        .font(.system(size: 14)).foregroundStyle(Color.inkKohlSoft)
                        .padding(.top, 24)
                }
                ForEach(recipes) { recipe in
                    NavigationLink(destination: FamilyRecipeDetailView(recipe: recipe, onRemoved: { Task { await reload() } })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipe.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.inkKohl)
                            Text(rowSubtitle(recipe)).font(.system(size: 12)).foregroundStyle(Color.inkKohlSoft).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .samaanCard()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Samaan.Space.md)
            .padding(.vertical, 12)
        }
        .background(Color.surfaceDoodh)
        .refreshable { await reload() }
        .task { await reload() }
        .sheet(item: $invite) { invite in
            ShareSheet(items: [invite.shareText])
        }
        .sheet(isPresented: $showMembers) {
            NavigationStack {
                FamilyMembersView(family: family) {
                    showMembers = false
                    onChange()
                    dismiss()
                }
            }
        }
        .heycatchScreen("Family")
    }

    private func rowSubtitle(_ r: FamilyRecipe) -> String {
        var parts: [String] = []
        if let a = r.attribution, !a.isEmpty { parts.append("from \(a)") }
        parts.append("added by \(r.addedByLabel)")
        return parts.joined(separator: " · ")
    }

    private func makeInvite() {
        errorMessage = nil
        Task { @MainActor in
            do {
                invite = try await FamilyService.shared.createInvite(familyID: family.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reload() async {
        do { recipes = try await FamilyService.shared.recipes(familyID: family.id) }
        catch { errorMessage = error.localizedDescription }
    }
}

extension FamilyInvite: Identifiable { var id: String { code } }

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Members

struct FamilyMembersView: View {
    @Environment(\.appEnv) private var appEnv
    @Environment(\.dismiss) private var dismiss
    let family: Family
    /// Called after leaving or deleting, so the family page can close.
    let onGone: () -> Void
    @State private var members: [FamilyMember] = []
    @State private var pending: PendingAction?
    @State private var errorMessage: String?
    @State private var showEditName = false

    private enum PendingAction: Identifiable {
        case remove(FamilyMember), transfer(FamilyMember), leave, delete
        var id: String {
            switch self {
            case .remove(let m): return "remove-\(m.userId)"
            case .transfer(let m): return "transfer-\(m.userId)"
            case .leave: return "leave"
            case .delete: return "delete"
            }
        }
    }

    private var myID: String? { appEnv.auth.currentUserID?.lowercased() }
    private var iAmOwner: Bool { members.contains { $0.isOwner && $0.userId.uuidString.lowercased() == myID } }

    var body: some View {
        List {
            Section {
                ForEach(members) { member in
                    HStack {
                        Text(member.displayLabel)
                        if member.userId.uuidString.lowercased() == myID { Text("(you)").foregroundStyle(.secondary) }
                        Spacer()
                        if member.isOwner { Text("Owner").font(.caption).foregroundStyle(.secondary) }
                    }
                    .swipeActions {
                        if iAmOwner && !member.isOwner {
                            Button("Remove", role: .destructive) { pending = .remove(member) }
                            Button(FamilyCopy.transferAction) { pending = .transfer(member) }.tint(Color.brandSaag)
                        }
                    }
                }
            } footer: {
                Text("\(members.count) of 50 members")
            }
            Section {
                Button(FamilyCopy.editNameAction) { showEditName = true }
                    .accessibilityIdentifier("families.members.editName")
            }
            Section {
                if iAmOwner {
                    Button(FamilyCopy.deleteAction, role: .destructive) { pending = .delete }
                } else {
                    Button(FamilyCopy.leaveAction, role: .destructive) { pending = .leave }
                }
            } footer: {
                if iAmOwner { Text("To leave, swipe on a member and make them owner first.") }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle(FamilyCopy.membersAction)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await reload() }
        .sheet(isPresented: $showEditName) {
            EditFamilyNameSheet { Task { await reload() } }
        }
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { action in
            Button(confirmLabel(action), role: .destructive) { perform(action) }
        } message: { action in
            Text(message(action))
        }
    }

    private var dialogTitle: String {
        switch pending {
        case .remove(let m): return "Remove \(m.displayLabel)?"
        case .transfer(let m): return "Make \(m.displayLabel) the owner?"
        case .leave: return "Leave \(family.name)?"
        case .delete: return "Delete \(family.name)?"
        case nil: return ""
        }
    }

    private func confirmLabel(_ a: PendingAction) -> String {
        switch a {
        case .remove: return "Remove"
        case .transfer: return FamilyCopy.transferAction
        case .leave: return FamilyCopy.leaveAction
        case .delete: return FamilyCopy.deleteAction
        }
    }

    private func message(_ a: PendingAction) -> String {
        switch a {
        case .remove: return FamilyCopy.removeMessage
        case .transfer: return "You'll stay in the family as a member."
        case .leave: return FamilyCopy.leaveMessage
        case .delete: return FamilyCopy.deleteMessage
        }
    }

    private func perform(_ a: PendingAction) {
        Task { @MainActor in
            do {
                switch a {
                case .remove(let m): try await FamilyService.shared.removeMember(familyID: family.id, userID: m.userId)
                case .transfer(let m): try await FamilyService.shared.transferOwnership(familyID: family.id, to: m.userId)
                case .leave:
                    try await FamilyService.shared.leave(familyID: family.id)
                    onGone(); return
                case .delete:
                    try await FamilyService.shared.deleteFamily(familyID: family.id)
                    onGone(); return
                }
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reload() async {
        do { members = try await FamilyService.shared.members(familyID: family.id) }
        catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - Family recipe card (read, save a copy, notes)

struct FamilyRecipeDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appEnv) private var appEnv
    @Environment(\.dismiss) private var dismiss
    let recipe: FamilyRecipe
    let onRemoved: () -> Void
    @State private var notes: [FamilyRecipeNote] = []
    @State private var memberNames: [UUID: String] = [:]
    @State private var draft = ""
    @State private var savedCopy = false
    @State private var errorMessage: String?

    private var isMine: Bool {
        recipe.addedBy?.uuidString.lowercased() == appEnv.auth.currentUserID?.lowercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(recipe.title).font(.cormorant(size: 30)).foregroundStyle(Color.inkKohl)
                if let a = recipe.attribution, !a.isEmpty {
                    Text("from \(a)").italic().foregroundStyle(Color.inkKohlSoft)
                }
                Text("Added by \(recipe.addedByLabel)").font(.system(size: 12)).foregroundStyle(Color.inkKohlSoft)
                if !recipe.ingredientPhrases.isEmpty {
                    Text("Ingredients").font(.headline)
                    ForEach(Array(recipe.ingredientPhrases.enumerated()), id: \.offset) { _, p in Text("• \(p)") }
                }
                if !recipe.steps.isEmpty {
                    Text("Steps").font(.headline)
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, s in Text("\(i + 1). \(s)") }
                }
                if let link = recipe.sourceUrl.flatMap({ URL(string: $0) }) {
                    Link("Open source link", destination: link)
                }
                if !isMine {
                    Button(savedCopy ? FamilyCopy.savedCopy : FamilyCopy.saveCopyAction) { saveCopy() }
                        .buttonStyle(SamaanSecondaryButtonStyle())
                        .disabled(savedCopy)
                        .accessibilityIdentifier("familyRecipe.saveCopy")
                } else {
                    Button("Remove from this family", role: .destructive) { remove() }
                        .buttonStyle(SamaanSecondaryButtonStyle())
                }
                notesSection
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .padding(.horizontal, Samaan.Space.md)
            .padding(.vertical, 12)
        }
        .background(Color.surfaceDoodh)
        .task { await loadNotes() }
        .heycatchScreen("Family Recipe")
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FamilyCopy.notesTitle).font(.headline)
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(memberNames[note.authorId] ?? FamilyCopy.unknownAuthor)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.inkKohlSoft)
                    Text(note.body)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).samaanCard()
            }
            TextField(FamilyCopy.notePlaceholder, text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Button("Add note") { addNote() }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// A local recipe the member owns. It syncs like any other recipe and survives leaving.
    private func saveCopy() {
        let copy = Recipe(
            title: recipe.title,
            rawTranscript: recipe.sourceUrl ?? "",
            extractedJSON: recipe.copyExtractedJSON,
            attribution: recipe.attribution,
            sourceKind: .copied
        )
        context.insert(copy)
        try? context.save()
        savedCopy = true
    }

    private func remove() {
        Task { @MainActor in
            do {
                try await FamilyService.shared.remove(recipeID: recipe.recipeId, from: recipe.familyId)
                onRemoved(); dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func loadNotes() async {
        notes = (try? await FamilyService.shared.notes(familyID: recipe.familyId, recipeID: recipe.recipeId)) ?? []
        let members = (try? await FamilyService.shared.members(familyID: recipe.familyId)) ?? []
        memberNames = Dictionary(members.map { ($0.userId, $0.displayLabel) }, uniquingKeysWith: { a, _ in a })
    }

    private func addNote() {
        let body = draft
        Task { @MainActor in
            do {
                let note = try await FamilyService.shared.addNote(familyID: recipe.familyId, recipeID: recipe.recipeId, body: body)
                notes.append(note); draft = ""
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - Add to family (from RecipeDetailView)

struct AddToFamilySheet: View {
    @Environment(\.dismiss) private var dismiss
    let recipeID: UUID
    @State private var families: [Family] = []
    @State private var selected: Set<UUID> = []
    @State private var original: Set<UUID> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text(FamilyCopy.addToFamilyBody)) {
                    if families.isEmpty { Text(FamilyCopy.emptyBody).foregroundStyle(.secondary) }
                    ForEach(families) { family in
                        Button {
                            if selected.contains(family.id) { selected.remove(family.id) } else { selected.insert(family.id) }
                        } label: {
                            HStack {
                                Text(family.name).foregroundStyle(Color.inkKohl)
                                Spacer()
                                if selected.contains(family.id) { Image(systemName: "checkmark").foregroundStyle(Color.brandSaag) }
                            }
                        }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(FamilyCopy.addToFamilyTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving || selected == original)
                }
            }
            .task {
                families = (try? await FamilyService.shared.myFamilies()) ?? []
                original = (try? await FamilyService.shared.familyIDs(containing: recipeID)) ?? []
                selected = original
            }
        }
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                for id in selected.subtracting(original) {
                    try await FamilyService.shared.add(recipeID: recipeID, to: id)
                }
                for id in original.subtracting(selected) {
                    try await FamilyService.shared.remove(recipeID: recipeID, from: id)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
