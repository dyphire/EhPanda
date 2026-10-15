import SwiftUI
import Resources
import Sharing
import SFSafeSymbols
import ComposableArchitecture
import WebDAVClient
import AppComponents

struct BackupSettingView: View {
    @Bindable private var store: StoreOf<BackupSettingReducer>
    @Shared(.webDAVConfiguration) private var webDAVConfig
    @State private var showsPassword = false

    init(store: StoreOf<BackupSettingReducer>) {
        self.store = store
    }

    private var webDAVBusy: Bool {
        store.webDAVTesting || store.webDAVBackingUp || store.webDAVListing
    }

    var body: some View {
        Form {
            exportSection
            importSection
            webDAVSection
            webDAVAutoBackupSection
        }
        .sheet(item: $store.destination.share, id: \.absoluteString) { url in
            ActivityView(activityItems: [url.wrappedValue])
        }
        .sheet(item: $store.destination.restoreFileList, id: \.self) { files in
            restoreFileList(files)
        }
        .toast($store.scope(state: \.toast, action: \.toast))
        .navigationTitle(.settingStateRouteBackup)
    }

    // MARK: Sections
    // Each Section is its own view so the `Form` body stays small enough for the type checker.

    private var exportSection: some View {
        Section {
            Button {
                store.send(.exportBackupButtonTapped)
            } label: {
                Label(.exportBackup, systemSymbol: .squareAndArrowUp)
            }
        } footer: {
            Text(.backupDescription)
        }
    }

    @ViewBuilder
    private var webDAVSection: some View {
        Section {
            HStack {
                Text(.webdavServer)
                TextField("https://dav.example.com", text: Binding($webDAVConfig.serverURL))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .onSubmit(normalizeServerURL)
            }
            HStack {
                Text(.webdavPath)
                TextField("/ehpanda", text: Binding($webDAVConfig.path))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text(.webdavUsername)
                TextField("", text: Binding($webDAVConfig.username))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text(.webdavPassword)
                Group {
                    if showsPassword {
                        TextField("", text: Binding($webDAVConfig.password))
                    } else {
                        SecureField("", text: Binding($webDAVConfig.password))
                    }
                }
                .multilineTextAlignment(.trailing)
                Button {
                    showsPassword.toggle()
                } label: {
                    Image(systemSymbol: showsPassword ? .eyeSlash : .eye)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            webDAVOperationRow(.webdavTestConnection, busy: store.webDAVTesting) {
                store.send(.webDAVTestConnectionButtonTapped)
            }
            webDAVOperationRow(.webdavBackupNow, busy: store.webDAVBackingUp) {
                store.send(.webDAVBackupButtonTapped)
            }
            webDAVOperationRow(.webdavRestore, busy: store.webDAVListing) {
                store.send(.webDAVRestoreButtonTapped)
            }
            if let lastBackupDate = webDAVConfig.lastBackupDate {
                HStack {
                    Text(.webdavLastBackup(
                        lastBackupDate.formatted(date: .abbreviated, time: .shortened)
                    ))
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text(.webdav)
        } footer: {
            Text(.webdavDescription)
        }
    }

    private var webDAVAutoBackupSection: some View {
        Section {
            HStack {
                Text(.webdavAutoBackup)
                Spacer()
                Toggle(.webdavAutoBackup, isOn: Binding($webDAVConfig.isEnabled))
                    .labelsHidden()
                    .frame(width: 50)
            }
            .contentShape(.rect)
        } footer: {
            Text(.webdavAutoBackupDescription)
        }
        .onChange(of: webDAVConfig.isEnabled) { _, isEnabled in
            if isEnabled && !webDAVConfig.isUsable {
                $webDAVConfig.withLock { $0.isEnabled = false }
                store.send(.webDAVAutoBackupRejected)
            }
        }
    }

    @ViewBuilder
    private var importSection: some View {
        Section {
            Button {
                store.send(.importBackupButtonTapped)
            } label: {
                Label(.importBackup, systemSymbol: .arrowDownDoc)
            }
            // `DocumentPicker` matches by extension: the modern `.fileImporter` greys out
            // files whose UTI got re-tagged, which is exactly how backups saved through a
            // share sheet or transferred between devices tend to end up.
            .sheet(isPresented: $store.destination.importBackup) {
                DocumentPicker { url in
                    if let url {
                        store.send(.delegate(.importFilePicked(url)))
                    }
                }
            }
            // Anchored to the import button — the dialog's trigger source, so the iPad popover
            // arrow points at it.
            .confirmationDialog(
                $store.scope(state: \.importBackupDialog, action: \.importBackupDialog)
            )
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func webDAVOperationRow(
        _ title: LocalizedStringResource, busy: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if busy {
                    ProgressView()
                }
            }
        }
        .disabled(!webDAVConfig.isUsable || webDAVBusy)
    }

    private func normalizeServerURL() {
        guard let url = webDAVConfig.normalizedServerURL else { return }
        let absoluteString = url.absoluteString
        $webDAVConfig.withLock { $0.serverURL = absoluteString }
    }

    @ViewBuilder
    private func restoreFileList(_ files: [WebDAVFile]) -> some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    Text(.webdavNoBackups)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(files) { file in
                        Button {
                            store.send(.webDAVFilePicked(file))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(file.name)
                                HStack(spacing: 4) {
                                    if let modifiedDate = file.modifiedDate {
                                        Text(modifiedDate.formatted(date: .abbreviated, time: .shortened))
                                    }
                                    Text(sizeString(file.size))
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(.webdavSelectBackup)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.RLocalizable.cancel) {
                        store.send(.destination(.dismiss))
                    }
                }
            }
        }
    }

    private func sizeString(_ size: Int) -> String {
        ByteCountFormatter().string(fromByteCount: Int64(size))
    }
}

struct BackupSettingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BackupSettingView(
                store: .init(initialState: .init(), reducer: BackupSettingReducer.init)
            )
        }
    }
}
