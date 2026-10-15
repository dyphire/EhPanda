import SwiftUI
import Resources
import UniformTypeIdentifiers
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
                // `.json` alone greys out backup files whose UTI got re-tagged (e.g. saved via the
                // share sheet to iCloud or third-party providers); `.data` accepts them since
                // `public.json` conforms to it. A non-JSON pick is still rejected by the decoder,
                // surfacing the "Backup failed" toast.
                .fileImporter(
                    isPresented: $store.destination.importBackup,
                    allowedContentTypes: [.json, .data]
                ) { result in
                    if case .success(let url) = result {
                        store.send(.delegate(.importFilePicked(url)))
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
