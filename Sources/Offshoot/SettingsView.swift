import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettings: View {
    @Bindable var store: RepoStore
    @AppStorage(MenuBarIcon.styleKey) private var iconStyle = MenuBarIcon.Style.leaf
    @AppStorage(GitHubCLI.settingKey) private var useGitHubCLI = false

    var body: some View {
        Form {
            Section {
                Picker("Menu bar icon", selection: $iconStyle) {
                    ForEach(MenuBarIcon.Style.allCases) { style in
                        Label {
                            Text(style.title)
                        } icon: {
                            Image(nsImage: MenuBarIcon.image(count: 0, style: style))
                        }
                        .tag(style)
                    }
                }
            }

            Section {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { store.loginItemStatus == .enabled },
                        set: { store.setLaunchAtLogin($0) }
                    ))
                if store.loginItemStatus == .requiresApproval {
                    LabeledContent("Offshoot needs your approval in Login Items.") {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    .font(.callout)
                }
            }

            Section {
                Picker("Fetch in the background", selection: $store.autoFetchMinutes) {
                    ForEach(RepoStore.autoFetchChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Never" : "Every \(minutes) minutes").tag(minutes)
                    }
                }
            } footer: {
                Text(
                    "Background fetches only update the ahead and behind counts. Nothing changes in your checkouts until you pull or choose Fetch All."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Check pull requests with GitHub CLI", isOn: $useGitHubCLI)
                    .disabled(GitHubCLI.executable == nil)
                    .onChange(of: useGitHubCLI) { Task { await store.refreshAll() } }
            } footer: {
                Text(
                    GitHubCLI.executable == nil
                        ? "Install the GitHub CLI (gh) and sign in with gh auth login to enable this."
                        : "Delete Merged Branches then removes a squash-merged branch only if its pull request was merged and contains every commit of the local branch. Branches whose pull request was closed without merging, or that have commits the pull request never got, are kept. Uses your gh sign-in; repositories not on GitHub fall back to the remote-branch rule."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { store.updateLoginItemStatus() }
    }
}

struct RepositorySettings: View {
    let store: RepoStore
    @State private var selection = Set<Repo.ID>()
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(store.repos) { repo in
                    RepositoryRow(repo: repo)
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .onDeleteCommand { removeSelection() }
            .overlay {
                if store.repos.isEmpty {
                    ContentUnavailableView(
                        "No Repositories",
                        systemImage: "folder.badge.plus",
                        description: Text("Add the git checkouts you want in the menu.")
                    )
                }
            }

            HStack(spacing: 0) {
                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "plus").frame(width: 24, height: 20)
                }
                .help("Add repositories")
                Divider().frame(height: 16)
                Button(action: removeSelection) {
                    Image(systemName: "minus").frame(width: 24, height: 20)
                }
                .disabled(selection.isEmpty)
                .help("Remove selected")
                Spacer()
                Text("Drag to reorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 500, height: 360)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder], allowsMultipleSelection: true) {
            result in
            guard case .success(let urls) = result else { return }
            Task { await store.add(urls) }
        }
    }

    private func removeSelection() {
        store.remove(selection)
        selection.removeAll()
    }
}

private struct RepositoryRow: View {
    let repo: Repo

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: repo.url.path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name)
                Text(abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if repo.loadError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(repo.loadError ?? "")
            }
        }
        .padding(.vertical, 2)
    }

    private var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return repo.url.path.hasPrefix(home) ? "~" + repo.url.path.dropFirst(home.count) : repo.url.path
    }
}
