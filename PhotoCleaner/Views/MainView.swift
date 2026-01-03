import Photos
import SwiftUI

struct MainView: View {
    @StateObject private var viewModel = CleanerViewModel()
    @ObservedObject var settingsStore: AppSettingsStore
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contentView
            }
            .navigationTitle("Photo Cleaner")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .disabled(!canShowSettings)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settingsStore: settingsStore)
            }
            .task {
                await viewModel.checkAuthorization(settings: settingsStore.settings)
            }
        }
    }

    private var canShowSettings: Bool {
        switch viewModel.state {
        case .idle, .ready, .completed, .error:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .idle:
            idleView

        case .requestingPermission:
            ProgressView("権限を確認中...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .scanning:
            scanningView

        case .ready:
            readyView

        case .savingKeep:
            ProgressView("Keepアルバムに保存中...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .deleting:
            ProgressView("削除中...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .completed(let deletedCount, let freedBytes):
            completedView(deletedCount: deletedCount, freedBytes: freedBytes)

        case .error(let message):
            errorView(message: message)
        }
    }

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("スキャンを開始してください")
                .font(.headline)
                .foregroundColor(.secondary)

            Button("スキャン開始") {
                Task {
                    await viewModel.scan(settings: settingsStore.settings)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("写真をスキャン中...")
                .font(.headline)

            Text("お気に入りやアルバム所属の写真を除外しています")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyView: some View {
        VStack(spacing: 0) {
            // Stats section
            VStack(spacing: 12) {
                StatRow(
                    icon: "trash",
                    iconColor: .red,
                    label: "削除対象",
                    value: "\(viewModel.deletionCount)枚"
                )

                if settingsStore.settings.generateContactSheet && viewModel.estimatedContactSheetCount > 0 {
                    StatRow(
                        icon: "calendar",
                        iconColor: .blue,
                        label: "コンタクトシート",
                        value: "約\(viewModel.estimatedContactSheetCount)ヶ月分"
                    )
                }

                StatRow(
                    icon: "internaldrive",
                    iconColor: .green,
                    label: "解放予定",
                    value: PhotoService.shared.formatBytes(viewModel.estimatedFreeBytes)
                )
            }
            .padding()
            .background(Color(.systemGroupedBackground))

            // Thumbnail grid
            if !viewModel.previewAssets.isEmpty {
                ThumbnailGridView(
                    assets: viewModel.previewAssets,
                    totalCount: viewModel.deletionCount
                )
                .frame(maxHeight: .infinity)
            } else {
                VStack {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    Text("削除対象の写真がありません")
                        .font(.headline)
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Action button
            VStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.executeCleanup(settings: settingsStore.settings)
                    }
                } label: {
                    Label("削除を実行する", systemImage: "trash")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!viewModel.isActionEnabled)

                Button {
                    Task {
                        await viewModel.scan(settings: settingsStore.settings)
                    }
                } label: {
                    Label("再スキャン", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }

    private func completedView(deletedCount: Int, freedBytes: Int64) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("削除完了")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                Text("\(deletedCount)枚の写真を削除しました")
                    .font(.headline)

                Text("\(PhotoService.shared.formatBytes(freedBytes))を解放しました")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button("新しいスキャンを開始") {
                viewModel.reset()
                Task {
                    await viewModel.scan(settings: settingsStore.settings)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("エラーが発生しました")
                .font(.title2)
                .fontWeight(.bold)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("再試行") {
                Task {
                    await viewModel.checkAuthorization(settings: settingsStore.settings)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)

            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    MainView(settingsStore: AppSettingsStore())
}
