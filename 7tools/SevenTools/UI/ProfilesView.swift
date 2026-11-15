import SwiftUI

struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 52

    var body: some View {
        Text(profile.emoji)
            .font(.system(size: size * 0.52))
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(Color(hue: profile.hue, saturation: 0.6, brightness: 1).opacity(0.55)), in: .circle)
    }
}

// Lista profili: zmiana, dodawanie, edycja, usuwanie
struct ProfilesView: View {
    var inSheet = false
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var hub: AudioHub
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Profile?
    @State private var adding = false
    @State private var confirmDelete: Profile?

    var body: some View {
        List {
            Section {
                ForEach(profiles.profiles) { p in
                    Button {
                        profiles.switchTo(p.id, hub: hub)
                        if inSheet { dismiss() }
                    } label: {
                        HStack(spacing: 14) {
                            ProfileAvatar(profile: p)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).spaced(.headline, .bold)
                                Text(p.id == profiles.currentID ? "Aktywny" : "Dotknij, aby przełączyć").spaced(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if p.id == profiles.currentID { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold).font(.system(size: 22)) }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { editing = p } label: { Label("Zmień nazwę i emoji", systemImage: "pencil") }
                        if profiles.profiles.count > 1 {
                            Button(role: .destructive) { confirmDelete = p } label: { Label("Usuń profil", systemImage: "trash") }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if profiles.profiles.count > 1 {
                            Button(role: .destructive) { confirmDelete = p } label: { Label("Usuń", systemImage: "trash") }
                        }
                        Button { editing = p } label: { Label("Edytuj", systemImage: "pencil") }.tint(.blue)
                    }
                }
                Button { adding = true } label: { Label("Dodaj profil", systemImage: "plus.circle.fill") }
            } header: { Text("Profile") }

            Section {
                Toggle("Pytaj, kto korzysta, przy starcie", isOn: $profiles.askOnLaunch)
            } footer: {
                Text("Konto to ta apka na tym telefonie. Wspólne dla wszystkich profili: biblioteka dźwięków, pobrane soundboardy i klucze AI. Osobne dla każdego profilu: pady, słuchanie, IKEA (lista i kalibracja), psikusy, gesty, licznik i ustawienia narzędzi.")
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Backdrop())
        .toolbar {
            if inSheet { ToolbarItem(placement: .confirmationAction) { Button("Gotowe") { dismiss() } } }
        }
        .sheet(isPresented: $adding) { ProfileForm(profile: nil, onDone: { name, emoji, copy in
            let p = profiles.add(name: name, emoji: emoji, copyCurrent: copy)
            profiles.switchTo(p.id, hub: hub)
            if inSheet { dismiss() }
        }) }
        .sheet(item: $editing) { p in
            ProfileForm(profile: p, onDone: { name, emoji, _ in profiles.update(p.id, name: name, emoji: emoji) })
        }
        .confirmationDialog("Usunąć profil „\(confirmDelete?.name ?? "")”? Jego ustawienia znikną, biblioteka dźwięków zostaje.",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Usuń", role: .destructive) { if let p = confirmDelete { profiles.delete(p.id) }; confirmDelete = nil }
        }
    }
}

struct ProfileForm: View {
    let profile: Profile?
    let onDone: (String, String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🙂"
    @State private var copy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Nazwa") { TextField("Np. Ola, Praca, Imprezy", text: $name) }
                Section("Awatar") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(ProfileBook.emojis, id: \.self) { e in
                            Button { emoji = e } label: {
                                Text(e).font(.system(size: 28)).frame(width: 48, height: 48)
                                    .glassEffect(emoji == e ? Glass.regular.tint(Theme.gold.opacity(0.6)) : Glass.regular, in: .circle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if profile == nil {
                    Section {
                        Toggle("Skopiuj obecne ustawienia", isOn: $copy)
                    } footer: { Text("Wyłączone: nowy profil zaczyna z czystymi ustawieniami (pady z domyślnymi dźwiękami).") }
                }
            }
            .navigationTitle(profile == nil ? "Nowy profil" : "Edytuj profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(profile == nil ? "Dodaj" : "Zapisz") { onDone(name, emoji, copy); dismiss() }
                }
            }
            .onAppear {
                if let p = profile { name = p.name; emoji = p.emoji }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// Ekran "Kto korzysta?" po starcie, jesli wlaczony
struct ProfilePicker: View {
    let done: () -> Void
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var hub: AudioHub

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 26) {
                Spacer()
                Text("Kto korzysta?").spaced(.largeTitle, .bold)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 18)], spacing: 18) {
                    ForEach(profiles.profiles) { p in
                        Button {
                            profiles.switchTo(p.id, hub: hub)
                            done()
                        } label: {
                            VStack(spacing: 8) {
                                ProfileAvatar(profile: p, size: 92)
                                    .overlay { if p.id == profiles.currentID { Circle().strokeBorder(Theme.gold, lineWidth: 3) } }
                                Text(p.name).spaced(.subheadline, .bold).foregroundStyle(.white).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 30)
                Spacer()
                Button("Zostań w „\(profiles.current.name)”") { done() }.buttonStyle(.glass).padding(.bottom, 30)
            }
        }
    }
}
