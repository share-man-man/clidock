import SwiftUI

/// The horizontal card row shared by clipboard history and pinboards.
struct PanelCardGrid<Content: View>: View {
    /// Builds the cards at the size determined by the panel height.
    @ViewBuilder let content: (CGSize) -> Content

    var body: some View {
        GeometryReader { panel in
            // Measure against the whole row so showing the scroller preserves the card size.
            let height = max(
                panel.size.height - DesignTokens.Grid.topPadding - DesignTokens.Grid.bottomPadding,
                DesignTokens.Grid.minCardHeight
            )
            // Keep the cards in proportion when the panel resizes.
            let size = CGSize(width: height * DesignTokens.Grid.cardAspectRatio, height: height)

            ScrollView(.horizontal) {
                LazyHGrid(rows: [GridItem(.fixed(height))], spacing: DesignTokens.Grid.cardSpacing) {
                    content(size)
                }
                .frame(height: height)
                .padding(.horizontal, DesignTokens.Grid.horizontalPadding)
                .padding(.top, DesignTokens.Grid.topPadding)
                // Center short rows horizontally and pin cards to the top. The flexible
                // space below them absorbs the native scroller when it is always visible.
                .frame(minWidth: panel.size.width, minHeight: 0, maxHeight: .infinity, alignment: .top)
            }
            // Allow card shadows to extend above the row on hover and selection.
            .scrollClipDisabled()
        }
    }
}
