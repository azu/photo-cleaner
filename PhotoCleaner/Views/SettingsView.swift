import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @Environment(\.dismiss) private var dismiss

    #if DEBUG
    @State private var debugPhotoCount: Int = 100
    @State private var debugMonthsBack: Int = 3
    @State private var debugDistributeEvenly: Bool = true
    @State private var debugPhotosPerDay: Int = 5
    @State private var debugSimulateClusters: Bool = true
    @State private var isGenerating: Bool = false
    @State private var generationProgress: Int = 0
    @State private var generatedMessage: String?
    @State private var generationError: String?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(
                        "バックアップ猶予日数: \(settingsStore.settings.backupGraceDays)日（\(String(format: "%.1f", Double(settingsStore.settings.backupGraceDays) / 365.0))年）",
                        value: $settingsStore.settings.backupGraceDays,
                        in: 7...1825,
                        step: 30
                    )
                } header: {
                    Text("削除条件")
                } footer: {
                    Text("この日数以上前の写真のみ削除対象になります。動画は対象外です。Amazon Photosへのバックアップが完了していることを前提とした猶予期間です。")
                }

                Section {
                    Toggle("コンタクトシートを生成", isOn: $settingsStore.settings.generateContactSheet)

                    if settingsStore.settings.generateContactSheet {
                        HStack {
                            Text("保存先アルバム")
                            Spacer()
                            TextField("Keep", text: $settingsStore.settings.keepAlbumName)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                        }
                    }
                } header: {
                    Text("振り返り設定")
                } footer: {
                    Text("削除前に月ごとのカレンダー形式のコンタクトシートを生成します。各日から撮影が集中した時間帯の写真を1枚選び、月間カレンダーとして保存します。")
                }

                Section {
                    Button("設定をリセット") {
                        settingsStore.reset()
                    }
                    .foregroundColor(.red)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photo Cleaner")
                            .font(.headline)

                        Text("Amazon Photosにバックアップ済みの写真をiPhoneから削除するアプリです。")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("お気に入りやアルバム所属の写真は保護されます。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("アプリについて")
                }

                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Debug Section
#if DEBUG
extension SettingsView {
    @ViewBuilder
    private var debugSection: some View {
        Section {
            Stepper(
                "総枚数: \(debugPhotoCount)枚",
                value: $debugPhotoCount,
                in: 20...500,
                step: 20
            )

            Stepper(
                "期間: \(debugMonthsBack)ヶ月前まで",
                value: $debugMonthsBack,
                in: 1...24,
                step: 1
            )

            Stepper(
                "1日あたり: \(debugPhotosPerDay)枚",
                value: $debugPhotosPerDay,
                in: 1...10
            )

            Toggle("日付ごとに均等配置", isOn: $debugDistributeEvenly)
            Toggle("時間クラスタをシミュレート", isOn: $debugSimulateClusters)

            Button {
                generateDummyPhotos()
            } label: {
                HStack {
                    Text("ダミー写真を生成")
                    Spacer()
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
            }
            .disabled(isGenerating)

            if isGenerating {
                ProgressView(value: Double(generationProgress), total: Double(debugPhotoCount)) {
                    Text("\(generationProgress) / \(debugPhotoCount)")
                        .font(.caption)
                }
            }

            if let message = generatedMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if let error = generationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        } header: {
            Text("デバッグ用写真生成")
        } footer: {
            Text("カレンダー型コンタクトシートのテスト用。クラスタシミュレートONで、同じ日に5分間隔で撮影されたような写真群を生成します。")
        }
    }

    private func generateDummyPhotos() {
        isGenerating = true
        generationProgress = 0
        generatedMessage = nil
        generationError = nil

        Task {
            do {
                let config = DebugPhotoGenerationConfig(
                    totalCount: debugPhotoCount,
                    monthsBack: debugMonthsBack,
                    distributeEvenly: debugDistributeEvenly,
                    photosPerDay: debugPhotosPerDay,
                    simulateClusters: debugSimulateClusters
                )

                let count = try await DebugPhotoService.shared.addDummyPhotos(
                    config: config
                ) { current, _ in
                    Task { @MainActor in
                        generationProgress = current
                    }
                }

                await MainActor.run {
                    generatedMessage = "\(count)枚生成完了"
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}
#endif

#Preview {
    SettingsView(settingsStore: AppSettingsStore())
}
