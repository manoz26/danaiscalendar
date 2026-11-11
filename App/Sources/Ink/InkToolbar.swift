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

    var body: some View {
        GeometryReader { proxy in
            bar(areaWidth: proxy.size.width)
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
        ForEach(InkTool.allCases, id: \.self) { tool in
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
                    ForEach(InkPalette.colors.indices, id: \.self) { index in
                        colorButton(index)
                    }
                }
                .opacity(ink.tools.tool.drawsInk ? 1 : 0.35)
            }
        }
        .frame(height: Self.colorRow * CGFloat(InkPalette.colors.count), alignment: .top)
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
        let names = [Text("Thin"), Text("Medium"), Text("Thick")]
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
        .accessibilityLabel(names[index])
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("toolbar.width.\(index + 1)")
    }

    private func colorButton(_ index: Int) -> some View {
        let color = InkPalette.colors[index]
        let selected = ink.tools.colorIndex == index
        return Button {
            ink.selectColor(index)
        } label: {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay(Circle().stroke(selected ? Paper.ink : Color.clear, lineWidth: 1.8))
                .frame(width: Self.toolSize, height: Self.colorRow)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.name(of: color))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("toolbar.color.\(color.key)")
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

    static func name(of color: InkColor) -> Text {
        switch color.key {
        case "pink": Text("Pink")
        case "black": Text("Black")
        case "red": Text("Red")
        case "blue": Text("Blue")
        case "green": Text("Green")
        case "purple": Text("Purple")
        default: Text(verbatim: color.key)
        }
    }
}

extension InkColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
