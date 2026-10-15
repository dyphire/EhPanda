import SwiftUI
import Resources
import SFSafeSymbols
import ComposableArchitecture
import AppComponents

struct BackupSettingView: View {
    @Bindable private var store: StoreOf<BackupSettingReducer>

    init(store: StoreOf<BackupSettingReducer>) {
        self.store = store
    }

    var body: some View {
        Form {
            Section {
                Button {
                    store.send(.exportBackupButtonTapped)
                } label: {
                    Label(.exportBackup, systemSymbol: .squareAndArrowUp)
                }
            } footer: {
                Text(.backupDescription)
            }
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
        .sheet(item: $store.destination.share, id: \.absoluteString) { url in
            ActivityView(activityItems: [url.wrappedValue])
        }
        .toast($store.scope(state: \.toast, action: \.toast))
        .navigationTitle(.settingStateRouteBackup)
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
