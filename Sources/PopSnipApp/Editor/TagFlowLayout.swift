// MARK: - TagFlowLayout.swift
// タグチップを実際の文字幅で詰めて折り返すフローレイアウト。
// LazyVGrid(.adaptive(minimum:)) は全セルを固定幅の等幅グリッドにしてしまい、
// 短いタグ名でも余白が間延びするため、Layout プロトコルで素直に実装する
// （UI_fix.md「スニペットの編集画面で、タグ一覧の間隔を詰める」）。

import SwiftUI

/// サブビューを提案幅の中で左詰めに並べ、収まらなくなったら次の行へ折り返す。
struct TagFlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrangeRows(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(CGFloat.zero) { partialHeight, row in
            partialHeight + row.height + (partialHeight > 0 ? lineSpacing : 0)
        }
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = arrangeRows(subviews: subviews, maxWidth: bounds.width)
        var originY = bounds.minY
        for row in rows {
            var originX = bounds.minX
            for element in row.elements {
                element.subview.place(
                    at: CGPoint(x: originX, y: originY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(element.size)
                )
                originX += element.size.width + spacing
            }
            originY += row.height + lineSpacing
        }
    }

    private struct RowElement {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        let elements: [RowElement]
        let width: CGFloat
        let height: CGFloat
    }

    private func arrangeRows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var currentElements: [RowElement] = []
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let widthIfAdded = currentWidth + (currentElements.isEmpty ? 0 : spacing) + size.width

            if currentElements.isEmpty == false, widthIfAdded > maxWidth {
                rows.append(makeRow(from: currentElements))
                currentElements = []
                currentWidth = 0
            }

            currentElements.append(RowElement(subview: subview, size: size))
            currentWidth += (currentElements.count > 1 ? spacing : 0) + size.width
        }

        if currentElements.isEmpty == false {
            rows.append(makeRow(from: currentElements))
        }

        return rows
    }

    private func makeRow(from elements: [RowElement]) -> Row {
        let width = elements.reduce(CGFloat.zero) { $0 + $1.size.width } + spacing * CGFloat(max(0, elements.count - 1))
        let height = elements.map(\.size.height).max() ?? 0
        return Row(elements: elements, width: width, height: height)
    }
}
