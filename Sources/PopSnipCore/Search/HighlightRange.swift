// MARK: - HighlightRange.swift
// 検索結果のヒット箇所を表す範囲。UTF-16 オフセットベースの NSRange を使うことで、
// Sendable かつ AttributedString / NSAttributedString どちらの描画経路にも変換しやすくする。

import Foundation

/// 文字列中のヒット箇所。
public typealias HighlightRange = NSRange
