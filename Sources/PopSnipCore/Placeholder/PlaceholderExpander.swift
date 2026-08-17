// MARK: - PlaceholderExpander.swift
// スニペット本文中の `{{ }}` トークンを、挿入直前の実際の値へ展開する。
// `PlaceholderParser.scan` で見つけたトークンのうち、`PlaceholderCatalog` に登録済みの
// キーワードだけを展開し、未知のキーワードは原文のまま残す（誤爆で本文が消えないことを優先）。

import Foundation

/// 展開後のテキストと、`{{cursor}}` が指定していたキャレット位置。
public struct ExpandedSnippetText: Equatable, Sendable {
    public let text: String
    /// `{{cursor}}` の位置。Accessibility 経路が `kAXSelectedTextRangeAttribute` に渡す
    /// UTF-16 オフセット（挿入したテキストの先頭からの相対位置）。トークンが無ければ nil。
    public let caretUTF16Offset: Int?
    /// 同じ位置を「挿入したテキストの末尾から何文字（書記素）戻るか」で表したもの。
    /// クリップボード経路はキャレット移動を左矢印キーの連続送出で行うため、送出回数は
    /// Character（書記素クラスタ）単位で数える必要があり、絵文字混じりの本文では
    /// UTF-16 オフセットと一致しない。両方を持たせて挿入経路ごとに使い分ける。
    public let caretCharacterOffsetFromEnd: Int?
}

/// プレースホルダ展開のエントリポイント。
public enum PlaceholderExpander {
    /// `body` 中の既知のプレースホルダを `context` の値で置き換える。
    public static func expand(_ body: String, context: PlaceholderContext) -> ExpandedSnippetText {
        let occurrences = PlaceholderParser.scan(body)
        guard occurrences.isEmpty == false else {
            return ExpandedSnippetText(text: body, caretUTF16Offset: nil, caretCharacterOffsetFromEnd: nil)
        }

        var output = ""
        output.reserveCapacity(body.utf16.count)
        var cursorUTF16Offset: Int?
        var cursorCharacterOffset: Int?
        var hasConsumedCursorToken = false
        var cursor = body.startIndex

        for occurrence in occurrences {
            output += body[cursor..<occurrence.range.lowerBound]

            if occurrence.isEscaped {
                // 先頭のバックスラッシュだけを取り除き、"{{keyword}}" をリテラルとして残す。
                let literalStart = body.index(after: occurrence.range.lowerBound)
                output += body[literalStart..<occurrence.range.upperBound]
            } else if occurrence.keyword == PlaceholderKind.cursor.rawValue {
                // {{cursor}} は表示テキストには何も出力しない。複数あっても最初の1つだけを
                // キャレット位置として採用し、残りは（トークン自体は）ただ除去する。
                if hasConsumedCursorToken == false {
                    hasConsumedCursorToken = true
                    cursorUTF16Offset = output.utf16.count
                    cursorCharacterOffset = output.count
                }
            } else if let definition = PlaceholderCatalog.definition(forKeyword: occurrence.keyword) {
                output += resolvedValue(for: definition.kind, argument: occurrence.argument, context: context)
            } else {
                // 未知のキーワード: 展開せず原文のまま残す。
                output += body[occurrence.range]
            }

            cursor = occurrence.range.upperBound
        }
        output += body[cursor...]

        let caretCharacterOffsetFromEnd = cursorCharacterOffset.map { output.count - $0 }
        return ExpandedSnippetText(
            text: output,
            caretUTF16Offset: cursorUTF16Offset,
            caretCharacterOffsetFromEnd: caretCharacterOffsetFromEnd
        )
    }

    private static func resolvedValue(
        for kind: PlaceholderKind,
        argument: String?,
        context: PlaceholderContext
    ) -> String {
        switch kind {
        case .date:
            return formattedDate(context: context, defaultPattern: "yyyy/MM/dd", argument: argument)
        case .time:
            return formattedDate(context: context, defaultPattern: "HH:mm", argument: argument)
        case .datetime:
            return formattedDate(context: context, defaultPattern: "yyyy/MM/dd HH:mm", argument: argument)
        case .year:
            return formattedDate(context: context, defaultPattern: "yyyy", argument: nil)
        case .month:
            return formattedDate(context: context, defaultPattern: "MM", argument: nil)
        case .day:
            return formattedDate(context: context, defaultPattern: "dd", argument: nil)
        case .weekday:
            return formattedDate(context: context, defaultPattern: "EEEE", argument: nil)
        case .clipboard:
            return context.clipboardText
        case .selection:
            return context.selectedText
        case .app:
            return context.appName
        case .uuid:
            return UUID().uuidString
        case .cursor:
            // 引数付き "{{cursor:...}}" のような想定外の書き方をされた場合の保険。
            // 通常は expand(_:context:) 側で先に特別扱いされるため、ここには来ない。
            return ""
        }
    }

    private static func formattedDate(
        context: PlaceholderContext,
        defaultPattern: String,
        argument: String?
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = context.locale
        formatter.timeZone = context.timeZone
        let trimmedArgument = argument?.trimmingCharacters(in: .whitespaces)
        formatter.dateFormat = (trimmedArgument?.isEmpty == false) ? trimmedArgument! : defaultPattern
        return formatter.string(from: context.now)
    }
}
