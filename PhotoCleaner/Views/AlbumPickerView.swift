import SwiftUI

struct AlbumPickerView: View {
    @Binding var selectedAlbums: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var availableAlbums: [String] = []
    private let defaultAlbum = "Keep"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(availableAlbums, id: \.self) { album in
                        AlbumRow(
                            name: album,
                            isSelected: selectedAlbums.contains(album),
                            isDefault: album == defaultAlbum
                        ) {
                            toggleAlbum(album)
                        }
                    }
                } header: {
                    Text("保護するアルバム")
                } footer: {
                    Text("選択したアルバム内の写真は削除されません。「Keep」はデフォルトで保護されます。")
                }
            }
            .navigationTitle("アルバム選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadAlbums()
            }
        }
    }

    private func loadAlbums() {
        let albums = PhotoService.shared.fetchUserAlbums()
        // Keepを先頭に、それ以外はソート済み
        if albums.contains(defaultAlbum) {
            availableAlbums = [defaultAlbum] + albums.filter { $0 != defaultAlbum }
        } else {
            availableAlbums = [defaultAlbum] + albums
        }

        // デフォルトアルバムが選択されていなければ追加
        if !selectedAlbums.contains(defaultAlbum) {
            selectedAlbums.append(defaultAlbum)
        }
    }

    private func toggleAlbum(_ album: String) {
        // Keepは常に選択状態を維持
        if album == defaultAlbum { return }

        if selectedAlbums.contains(album) {
            selectedAlbums.removeAll { $0 == album }
        } else {
            selectedAlbums.append(album)
        }
    }
}

private struct AlbumRow: View {
    let name: String
    let isSelected: Bool
    let isDefault: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(name)
                    .foregroundColor(isDefault ? .secondary : .primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }

                if isDefault {
                    Text("デフォルト")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(isDefault)
    }
}

#Preview {
    AlbumPickerView(selectedAlbums: .constant(["Keep"]))
}
