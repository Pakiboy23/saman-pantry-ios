import SwiftUI

/// Pro-only create flow. Free users never reach this sheet; they hit the paywall
/// from the Family book tab instead. Member invites are local for now — shared
/// cookbook sync ships with the Pro products after App Store approval.
struct CreateFamilyCookbookView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("samaan.familyCookbook.name") private var cookbookName = ""
    @AppStorage("samaan.familyCookbook.members") private var membersRaw = ""

    @State private var name: String = ""
    @State private var memberEmail = ""
    @State private var members: [String] = []
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Create your family cookbook")
                        .font(.cormorant(size: 28))
                        .foregroundStyle(Color.inkKohl)

                    Text("One place for every recipe, from every generation. Invite family members so they can read and cook from it for free.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkKohlSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("COOKBOOK NAME")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.inkKohlSoft)
                            .kerning(0.8)
                        TextField("e.g. Khan family recipes", text: $name)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.inkKohl)
                            .textFieldStyle(.plain)
                            .accessibilityIdentifier("cookbook.name")
                    }
                    .padding(Samaan.Space.md)
                    .samaanCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ADD FAMILY MEMBERS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.inkKohlSoft)
                            .kerning(0.8)

                        HStack(spacing: 8) {
                            TextField("Email", text: $memberEmail)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.inkKohl)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("cookbook.memberEmail")
                            Button("Add") { addMember() }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.brandSaag)
                                .disabled(!canAddMember)
                        }

                        if members.isEmpty {
                            Text("They can read and cook from your cookbook for free.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.inkKohlSoft)
                        } else {
                            ForEach(members, id: \.self) { email in
                                HStack {
                                    Text(email)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.inkKohl)
                                    Spacer()
                                    Button {
                                        members.removeAll { $0 == email }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color.inkKohlSoft)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(email)")
                                }
                            }
                        }
                    }
                    .padding(Samaan.Space.md)
                    .samaanCard()

                    if didSave {
                        Text("Cookbook saved on this device. Family invites will sync once Samaan Pro sharing is live.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.brandSaag)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Save cookbook") { save() }
                        .buttonStyle(SamaanPrimaryButtonStyle())
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("cookbook.save")
                }
                .padding(Samaan.Space.lg)
            }
            .background(Color.surfaceDoodh.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.brandSaag)
                }
            }
            .onAppear {
                name = cookbookName
                members = membersRaw
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
    }

    private var canAddMember: Bool {
        let email = memberEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.contains("@") && !members.contains(where: { $0.caseInsensitiveCompare(email) == .orderedSame })
    }

    private func addMember() {
        let email = memberEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAddMember else { return }
        members.append(email)
        memberEmail = ""
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cookbookName = trimmed
        membersRaw = members.joined(separator: ",")
        didSave = true
    }
}
