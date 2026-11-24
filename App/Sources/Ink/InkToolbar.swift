import PlannerCore
import SwiftUI

/// The floating, vertical tool bar of the iPad, in black and white like the paper: the
/// only colour is in the ink dots. Drag the grip to move it to the other edge; the
/// chevron folds it to show just the current tool.
struct InkToolbarOverlay: View {
    let ink: InkController
    @GestureState private var drag: CGSize = .zero

    private static let area = "inkToolbarArea"
    private static let width: CGFloat = 52
    private static let toolSize: CGFloat = 38
    private static let colorRow: CGFloat = 28
    /// Under the colours: the highlighter's opacity, when it is selected (empty otherwise, so
    /// the buttons below never move).
    private static let opacityRow: CGFloat = 28
    private static let favoriteRow: CGFloat = 34
    /// More colours than this go in two columns.
    private static let colorsPerColumn = 6

    var body: some View {
        GeometryReader { proxy in
            // A small screen (or many colours and favourites): the bar scrolls instead of
            // running off the page.
            ViewThatFits(in: .vertical) {
                bar(areaWidth: proxy.size.width)
                ScrollView(.vertical, showsIndicators: false) {
                    bar(areaWidth: proxy.size.width)
                }
                .frame(width: Self.width + 24)
            }
                .offset(drag)
                .frame(
                    maxWidth: .infinity, maxHeight: .infinity,
                    alignment: ink.toolbarSide == .leading ? .leading : .trailing
                )
                .padding(.horizontal, 10)
                .animation(.snappy(duration: 0.25), value: ink.toolbarSide)
                .animation(.snappy(duration: 0.2), value: ink.toolbarCollapsed)
        }
        .coordinateSpace(.named(Self.area))
    }

    // MARK: - Bar

    private func bar(areaWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            grip(areaWidth: areaWidth)
            if ink.toolbarCollapsed {
                collapsed
            } else {
                expanded
            }
        }
        .padding(.bottom, 6)
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Paper.background)
                .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Paper.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools"))
        .accessibilityIdentifier("toolbar")
    }

    private func grip(areaWidth: CGFloat) -> some View {
        Capsule()
            .fill(Paper.secondary)
            .frame(width: 22, height: 4)
            .frame(width: Self.width, height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.area))
                    .updating($drag) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        let x = value.predictedEndLocation.x
                        ink.moveToolbar(to: x < areaWidth / 2 ? .leading : .trailing)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(Text("Move tools"))
            .accessibilityHint(Text("Moves the tools to the other side of the page."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { ink.moveToolbar(to: ink.toolbarSide.other) }
            .accessibilityIdentifier("toolbar.grip")
    }

    @ViewBuilder
    private var expanded: some View {
        let palette = ink.settings.palette
        ForEach(ink.settings.toolbarTools, id: \.self) { tool in
            toolButton(tool)
        }
        divider
        ForEach(0..<InkToolState.widthCount, id: \.self) { index in
            widthButton(index)
        }
        .opacity(ink.tools.tool.hasWidths ? 1 : 0.3)
        .disabled(!ink.tools.tool.hasWidths)
        divider
        Group {
            if ink.tools.tool == .eraser {
                eraserModes
            } else {
                VStack(spacing: 0) {
                    colors(palette)
                        .opacity(ink.tools.tool.drawsInk ? 1 : 0.35)
                    if ink.tools.tool == .highlighter {
                        highlighterOpacities
                    }
                }
            }
        }
        .frame(height: Self.colorRow * CGFloat(Self.colorRows(palette.count)) + Self.opacityRow, alignment: .top)
        favorites(palette)
        divider
        iconButton("arrow.uturn.backward", label: Text("Undo"), identifier: "toolbar.undo", enabled: ink.canUndo) {
            ink.undo()
        }
        iconButton("arrow.uturn.forward", label: Text("Redo"), identifier: "toolbar.redo", enabled: ink.canRedo) {
            ink.redo()
        }
        divider
        iconButton("chevron.compact.up", label: Text("Hide tools"), identifier: "toolbar.collapse") {
            ink.setToolbarCollapsed(true)
        }
    }

    /// Rows of colour dots: one column up to six, two columns of up to six beyond.
    private static func colorRows(_ count: Int) -> Int {
        count <= colorsPerColumn ? count : (count + 1) / 2
    }

    @ViewBuilder
    private func colors(_ palette: [InkColor]) -> some View {
        if palette.count <= Self.colorsPerColumn {
            ForEach(palette.indices, id: \.self) { index in
                colorButton(index, palette: palette, width: Self.toolSize)
            }
        } else {
            let rows = Self.colorRows(palette.count)
            HStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { column in
                    VStack(spacing: 0) {
                        ForEach(Array(palette.indices.dropFirst(column * rows).prefix(rows)), id: \.self) { index in
                            colorButton(index, palette: palette, width: (Self.width - 6) / 2)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: Self.width - 6, height: Self.colorRow * CGFloat(rows), alignment: .top)
        }
    }

    /// Favourite pens under the colours: the tool's icon in its colour; one tap takes it,
    /// holding it removes it. The star adds the pen in use.
    @ViewBuilder
    private func favorites(_ palette: [InkColor]) -> some View {
        let favorites = ink.settings.favorites
        let canAdd = favorites.count < FavoritePen.maxCount && ink.tools.tool.drawsInk
        if !favorites.isEmpty || canAdd {
            divider
            ForEach(Array(favorites.enumerated()), id: \.element.id) { index, favorite in
                favoriteButton(favorite, number: index + 1, palette: palette)
            }
            if canAdd {
                Button {
                    ink.addFavorite()
                } label: {
                    Image(systemName: "star")
                        .font(.system(size: 16))
                        .foregroundStyle(Paper.secondary)
                        .frame(width: Self.toolSize, height: Self.favoriteRow)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add the pen in use to favourites"))
                .accessibilityIdentifier("toolbar.favorite.add")
            }
        }
    }

    private func favoriteButton(_ favorite: FavoritePen, number: Int, palette: [InkColor]) -> some View {
        let selected = ink.tools.isUsing(favorite)
        let weight: Font.Weight = switch favorite.widthIndex {
        case 0: .light
        case 1: .regular
        default: .semibold
        }
        let opacity = favorite.tool == .highlighter
            ? max(0.45, InkOpacities.highlighter[min(max(favorite.opacityIndex, 0), InkOpacities.highlighter.count - 1)])
            : 1
        return Button {
            ink.select(favorite)
        } label: {
            Image(systemName: Self.symbol(for: favorite.tool, eraserMode: .partial))
                .font(.system(size: 18, weight: weight))
                .foregroundStyle(favorite.color.swiftUIColor.opacity(opacity))
                .frame(width: Self.toolSize, height: Self.favoriteRow)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Paper.tab : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                ink.removeFavorite(favorite.id)
            } label: {
                Label {
                    Text("Remove from favourites")
                } icon: {
                    Image(systemName: "star.slash")
                }
            }
        }
        .accessibilityLabel(Self.describe(favorite, palette: palette))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("toolbar.favorite.\(number)")
    }

    private var collapsed: some View {
        Button {
            ink.setToolbarCollapsed(false)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: Self.symbol(for: ink.tools.tool, eraserMode: ink.tools.eraserMode))
                    .font(.system(size: 19))
                    .foregroundStyle(Paper.ink)
                if ink.tools.tool.drawsInk {
                    Circle()
                        .fill(ink.tools.color.swiftUIColor)
                        .frame(width: 12, height: 12)
                }
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Paper.ink)
            }
            .frame(width: Self.toolSize, height: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Show tools"))
        .accessibilityIdentifier("toolbar.expand")
    }

    // MARK: - Buttons

    private func toolButton(_ tool: InkTool) -> some View {
        let selected = ink.tools.tool == tool
        return Button {
            ink.select(tool)
        } label: {
            Image(systemName: Self.symbol(for: tool, eraserMode: ink.tools.eraserMode))
                .font(.system(size: 18))
                .foregroundStyle(selected ? Paper.background : Paper.ink)
                .frame(width: Self.toolSize, height: Self.toolSize)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Paper.ink : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.name(of: tool))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("toolbar.tool.\(tool.rawValue)")
    }

    private func widthButton(_ index: Int) -> some View {
        let selected = ink.tools.tool.hasWidths && ink.tools.widthIndex == index
        let thickness: [CGFloat] = [1.5, 3, 5.5]
        return Button {
            ink.selectWidth(index)
        } label: {
            Capsule()
                .fill(Paper.ink)
                .frame(width: 20, height: thickness[index])
                .frame(width: Self.toolSize, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Paper.tab : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.widthName(index))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("toolbar.width.\(index + 1)")
    }

    private func colorButton(_ index: Int, palette: [InkColor], width: CGFloat) -> some View {
        let color = palette[index]
        let selected = ink.tools.colorIndex(in: palette) == index
        return Button {
            ink.selectColor(index)
        } label: {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay(Circle().stroke(selected ? Paper.ink : Color.clear, lineWidth: 1.8))
                .frame(width: width, height: Self.colorRow)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.name(of: color, at: index))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("toolbar.color.\(color.key)")
    }

    /// Three levels side by side, faint to strong: small upright marks in black at each
    /// opacity (black and white, like the rest of the bar).
    private var highlighterOpacities: some View {
        HStack(spacing: 0) {
            ForEach(InkOpacities.highlighter.indices, id: \.self) { index in
                opacityButton(index)
            }
        }
        .frame(width: Self.width - 4, height: Self.opacityRow)
    }

    private func opacityButton(_ index: Int) -> some View {
        let selected = ink.tools.highlighterOpacityIndex == index
        let names = [Text("Faint highlighter"), Text("Medium highlighter"), Text("Strong highlighter")]
        return Button {
            ink.selectHighlighterOpacity(index)
        } label: {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Paper.ink.opacity(InkOpacities.highlighter[index]))
                .overlay(
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .stroke(Paper.hairline, lineWidth: 0.5)
                )
                .frame(width: 8, height: 15)
                .padding(2.5)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(selected ? Paper.ink : Color.clear, lineWidth: 1.5)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(names[index])
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("toolbar.opacity.\(index + 1)")
    }

    private var eraserModes: some View {
        VStack(spacing: 4) {
            eraserModeButton(.partial, label: Text("Erase what you touch"))
            eraserModeButton(.wholeStroke, label: Text("Erase whole lines"))
        }
        .padding(.top, 2)
    }

    private func eraserModeButton(_ mode: EraserMode, label: Text) -> some View {
        let selected = ink.tools.eraserMode == mode
        return Button {
            ink.selectEraserMode(mode)
        } label: {
            Image(systemName: Self.symbol(for: .eraser, eraserMode: mode))
                .font(.system(size: 17))
                .foregroundStyle(Paper.ink)
                .frame(width: Self.toolSize, height: Self.toolSize)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Paper.tab : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("toolbar.eraser.\(mode.rawValue)")
    }

    private func iconButton(
        _ systemName: String, label: Text, identifier: String, enabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Paper.ink)
                .opacity(enabled ? 1 : 0.25)
                .frame(width: Self.toolSize, height: Self.toolSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var divider: some View {
        Rectangle()
            .fill(Paper.hairline)
            .frame(width: 26, height: 1)
            .padding(.vertical, 4)
    }

    // MARK: - Names and symbols

    static func symbol(for tool: InkTool, eraserMode: EraserMode) -> String {
        switch tool {
        case .pen: "pencil.tip"
        case .pencil: "pencil"
        case .highlighter: "highlighter"
        case .eraser: eraserMode == .partial ? "eraser" : "eraser.line.dashed"
        case .lasso: "lasso"
        }
    }

    static func name(of tool: InkTool) -> Text {
        switch tool {
        case .pen: Text("Pen")
        case .pencil: Text("Pencil")
        case .highlighter: Text("Highlighter")
        case .eraser: Text("Eraser")
        case .lasso: Text("Lasso")
        }
    }

    /// The first six by name; the ones she added by their place ("Colour 7").
    static func name(of color: InkColor, at index: Int? = nil) -> Text {
        switch color.key {
        case "pink": return Text("Pink")
        case "black": return Text("Black")
        case "red": return Text("Red")
        case "blue": return Text("Blue")
        case "green": return Text("Green")
        case "purple": return Text("Purple")
        default:
            if let index {
                let number = index + 1
                return Text("Colour \(number)", comment: "A colour she added to the palette, by its place, e.g. 'Colour 7'.")
            }
            return Text("Own colour", comment: "A colour she added, not in the palette any more.")
        }
    }

    static func widthName(_ index: Int) -> Text {
        switch index {
        case 0: Text("Thin")
        case 1: Text("Medium")
        default: Text("Thick")
        }
    }

    /// E.g. "Highlighter, Blue, Thick, Faint highlighter".
    static func describe(_ favorite: FavoritePen, palette: [InkColor]) -> Text {
        let index = palette.firstIndex { $0.key == favorite.color.key }
        let separator = Text(verbatim: ", ")
        let text = name(of: favorite.tool) + separator + name(of: favorite.color, at: index) + separator + widthName(favorite.widthIndex)
        guard favorite.tool == .highlighter else { return text }
        let level: Text = switch min(max(favorite.opacityIndex, 0), 2) {
        case 0: Text("Faint highlighter")
        case 1: Text("Medium highlighter")
        default: Text("Strong highlighter")
        }
        return text + separator + level
    }
}

extension InkColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
