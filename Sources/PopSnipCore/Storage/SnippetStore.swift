// MARK: - SnippetStore.swift
// snippets.json の読み書き・外部編集の反映・CRUD 操作を担当する。
// 外部編集の反映は mtime 比較による遅延リロード（パネル表示時に reloadIfNeeded を呼ぶ）で行い、
// DispatchSource による常時監視は行わない。

import Foundation
import OSLog

/// スニペットライブラリの永続化ストア。
@MainActor
public final class SnippetStore: ObservableObject {
    @Published public private(set) var library: SnippetLibrary {
        didSet {
            revision += 1
            cachedSearchIndex = nil
        }
    }

    /// `library` が変更されるたびに単調増加するリビジョン番号。
    /// 呼び出し側（検索結果キャッシュなど）が「このリビジョンでは計算済みか」を判定するのに使う。
    public private(set) var revision = 0

    public let fileURL: URL
    private var lastKnownModificationDate: Date?
    private let fileManager: FileManager
    private var cachedSearchIndex: SnippetSearchIndex?

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        let resolvedURL = fileURL ?? SnippetStore.defaultFileURL()
        self.fileURL = resolvedURL
        self.fileManager = fileManager
        self.library = SnippetStore.load(from: resolvedURL, fileManager: fileManager) ?? .empty
        self.lastKnownModificationDate = SnippetStore.modificationDate(of: resolvedURL, fileManager: fileManager)
    }

    /// 検索用インデックスを返す。`library` が前回構築時から変わっていなければ再利用する。
    /// タイトル・本文・タグ名の小文字化を、キーストロークのたびではなくライブラリ更新のたびに1回で済ませるため。
    public func searchIndex() -> SnippetSearchIndex {
        if let cachedSearchIndex {
            return cachedSearchIndex
        }
        let index = SnippetSearchIndex(snippets: library.snippets, tags: library.tags)
        cachedSearchIndex = index
        return index
    }

    /// 既定の保存先。設定でカスタムパスが指定されていればそちらを優先する。
    public static func defaultFileURL(userDefaults: UserDefaults = .standard) -> URL {
        if
            let customPath = AppSettingsResolver.resolveSnippetFilePath(userDefaults: userDefaults),
            customPath.isEmpty == false
        {
            return URL(fileURLWithPath: customPath)
        }
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupportDirectory
            .appendingPathComponent("PopSnip", isDirectory: true)
            .appendingPathComponent("snippets.json", isDirectory: false)
    }

    // MARK: - 外部編集の反映

    /// ファイルの mtime が前回確認時から変化していればディスクから読み直す。
    /// パネル表示のたびに呼び出す想定（常時監視はしない）。
    public func reloadIfNeeded() {
        let currentModificationDate = Self.modificationDate(of: fileURL, fileManager: fileManager)
        guard currentModificationDate != lastKnownModificationDate else {
            return
        }
        lastKnownModificationDate = currentModificationDate
        guard let reloadedLibrary = Self.load(from: fileURL, fileManager: fileManager) else {
            return
        }
        library = reloadedLibrary
    }

    // MARK: - スニペット CRUD

    public func upsertSnippet(_ snippet: Snippet) {
        var updatedSnippet = snippet
        updatedSnippet.updatedAt = Date()
        if let index = library.snippets.firstIndex(where: { $0.id == snippet.id }) {
            library.snippets[index] = updatedSnippet
        } else {
            library.snippets.append(updatedSnippet)
        }
        save()
    }

    public func deleteSnippet(id: UUID) {
        library.snippets.removeAll { $0.id == id }
        save()
    }

    /// 挿入成功時に使用回数・最終使用日時を更新する。
    public func recordUsage(of snippetID: UUID, usedAt: Date = Date()) {
        guard let index = library.snippets.firstIndex(where: { $0.id == snippetID }) else {
            return
        }
        library.snippets[index].usageCount += 1
        library.snippets[index].lastUsedAt = usedAt
        save()
    }

    /// お気に入りの ON/OFF を切り替える。`upsertSnippet` と異なり `updatedAt` は更新しない
    /// （お気に入り切り替えを「編集」として扱わないため）。
    public func toggleFavorite(id: UUID) {
        guard let index = library.snippets.firstIndex(where: { $0.id == id }) else {
            return
        }
        library.snippets[index].isFavorite.toggle()
        save()
    }

    // MARK: - タグ CRUD

    public func upsertTag(_ tag: SnippetTag) {
        if let index = library.tags.firstIndex(where: { $0.id == tag.id }) {
            library.tags[index] = tag
        } else {
            library.tags.append(tag)
        }
        save()
    }

    /// タグを削除し、全スニペットの参照からも取り除く（ID 参照方式のため手動で整合を取る）。
    public func deleteTag(id: UUID) {
        library.tags.removeAll { $0.id == id }
        for index in library.snippets.indices {
            library.snippets[index].tagIDs.removeAll { $0 == id }
        }
        save()
    }

    /// 新規タグを名前から作成し、色は `TagColorAssigner` で自動割り当てする。
    @discardableResult
    public func createTag(name: String) -> SnippetTag {
        let color = TagColorAssigner.nextColor(existingTags: library.tags)
        let tag = SnippetTag(name: name, colorHex: color)
        upsertTag(tag)
        return tag
    }

    // MARK: - 永続化

    public func save() {
        do {
            try persist(library)
            lastKnownModificationDate = Self.modificationDate(of: fileURL, fileManager: fileManager)
        } catch {
            Logger.storage.error("スニペットファイルの保存に失敗: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist(_ library: SnippetLibrary) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) == false {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL, fileManager: FileManager) -> SnippetLibrary? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SnippetLibrary.self, from: data)
        } catch {
            Logger.storage.error(
                "スニペットファイルの読み込みに失敗、破損ファイルとして退避: \(error.localizedDescription, privacy: .public)"
            )
            backupCorruptedFile(at: url, fileManager: fileManager)
            return nil
        }
    }

    /// 破損した JSON ファイルをタイムスタンプ付きでリネームして残す（データ喪失を防ぐ）。
    private static func backupCorruptedFile(at url: URL, fileManager: FileManager) {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("snippets.broken-\(timestamp).json")
        try? fileManager.moveItem(at: url, to: backupURL)
    }

    private static func modificationDate(of url: URL, fileManager: FileManager) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }
}
