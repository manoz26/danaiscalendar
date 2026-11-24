import PlannerCore
import SwiftUI
import UIKit

// MARK: - Pens and colours

/// Settings → Pens and colours (iPad): the palette (change, add, remove, reorder), the
/// three widths of each tool, favourite pens, and which tools the toolbar shows.
struct PensSettingsView: View {
    let settings: SettingsBook
    let ink: InkController

    @State private var tool: InkTool = .pen
    @State private var confirmReset = false

    private static let widthTools: [InkTool] = [.pen, .pencil, .highlighter, .eraser]

    var body: some View {
        List {
            colorsSection
            widthsSection
            favoritesSection
            toolbarSection
            Section {
                Button {
                    confirmReset = true
                } label: {
                    Text("Reset pens and colours")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("pens.reset")
                .listRowBackground(Paper.background)
            }
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
        .scrollContentBackground(.hidden)
        .background(Paper.fill)
        .navigationTitle(Text("Pens and colours"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .font(.inter(.medium, size: 17, relativeTo: .body))
                    .accessibilityIdentifier("pens.edit")
            }
        }
        .confirmationDialog(Text("Reset pens and colours?"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button {
                settings.reset([.palette, .widths, .favorites, .toolbarTools])
            } label: {
                Text("Reset")
            }
            .accessibilityIdentifier("pens.confirmReset")
            Button(role: .cancel) {} label: { Text("Cancel") }
        } message: {
            Text("The six colours, the widths and all the tools come back; your favourite pens are removed. Your handwriting does not change.")
        }
    }

    // MARK: Colours

    private var palette: [InkColor] { settings.settings.palette }

    private var colorsSection: some View {
        Section {
            ForEach(Array(palette.enumerated()), id: \.element.key) { index, color in
                ColorPicker(selection: colorBinding(index), supportsOpacity: false) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 20, height: 20)
                        InkToolbarOverlay.name(of: color, at: index)
                            .font(.inter(.regular, size: 17, relativeTo: .body))
                            .foregroundStyle(Paper.ink)
                    }
                }
                .accessibilityIdentifier("pens.color.\(index + 1)")
                .listRowBackground(Paper.background)
            }
            .onMove { from, to in
                var moved = palette
                moved.move(fromOffsets: from, toOffset: to)
                settings.setPalette(moved)
            }
            .onDelete { offsets in
                guard palette.count > offsets.count else { return }
                var remaining = palette
                remaining.remove(atOffsets: offsets)
                settings.setPalette(remaining)
            }
            if palette.count < InkPalette.maxCount {
                Button {
                    settings.setPalette(palette + [InkColor.custom(red: 0.07, green: 0.64, blue: 0.64)])
                } label: {
                    Label {
                        Text("Add a colour")
                    } icon: {
                        Image(systemName: "plus")
                    }
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Paper.ink)
                }
                .accessibilityIdentifier("pens.addColor")
                .listRowBackground(Paper.background)
            }
        } header: {
            CapsLabel("Colours")
        } footer: {
            Text("Tap a colour to change it. With Edit you can remove colours and change their order. Up to 12; ink already written keeps its colour.")
                .font(.inter(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Paper.secondary)
        }
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { palette.indices.contains(index) ? palette[index].swiftUIColor : .black },
            set: { newValue in
                guard palette.indices.contains(index) else { return }
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                UIColor(newValue).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                var edited = palette
                edited[index] = edited[index].with(red: red, green: green, blue: blue)
                guard edited != palette else { return }
                settings.setPalette(edited)
            }
        )
    }

    // MARK: Widths

    private var widthsSection: some View {
        Section {
            Picker(selection: $tool) {
                ForEach(Self.widthTools, id: \.self) { tool in
                    InkToolbarOverlay.name(of: tool).tag(tool)
                }
            } label: {
                Text("Tool")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("pens.widthTool")
            .listRowBackground(Paper.background)
            ForEach(0..<InkToolState.widthCount, id: \.self) { index in
                WidthRow(
                    name: InkToolbarOverlay.widthName(index),
                    width: widthBinding(index),
                    range: InkWidths.range(for: tool),
                    isHighlighter: tool == .highlighter
                )
                .accessibilityIdentifier("pens.width.\(index + 1)")
                .listRowBackground(Paper.background)
            }
        } header: {
            CapsLabel("Widths")
        } footer: {
            Text("The three widths of each tool in the toolbar.")
                .font(.inter(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Paper.secondary)
        }
    }

    private func widthBinding(_ index: Int) -> Binding<CGFloat> {
        let tool = tool
        return Binding(
            get: { settings.settings.widths.value(for: tool, index: index) ?? 1 },
            set: { newValue in
                var widths = settings.settings.widths
                widths.set(newValue, for: tool, index: index)
                settings.setWidths(widths)
            }
        )
    }

    // MARK: Favourite pens

    private var favoritesSection: some View {
        let favorites = settings.settings.favorites
        return Section {
            ForEach(favorites) { favorite in
                HStack(spacing: 12) {
                    Image(systemName: InkToolbarOverlay.symbol(for: favorite.tool, eraserMode: .partial))
                        .font(.system(size: 18))
                        .foregroundStyle(favorite.color.swiftUIColor)
                        .frame(width: 24)
                    InkToolbarOverlay.describe(favorite, palette: palette)
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pens.favorite")
                .listRowBackground(Paper.background)
            }
            .onMove { from, to in
                var moved = favorites
                moved.move(fromOffsets: from, toOffset: to)
                settings.setFavorites(moved)
            }
            .onDelete { offsets in
                var remaining = favorites
                remaining.remove(atOffsets: offsets)
                settings.setFavorites(remaining)
            }
            if favorites.count < FavoritePen.maxCount, let current = ink.tools.favorite() {
                Button {
                    settings.setFavorites(favorites + [current])
                } label: {
                    Label {
                        Text("Add the pen in use")
                    } icon: {
                        Image(systemName: "star")
                    }
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Paper.ink)
                }
                .accessibilityIdentifier("pens.addFavorite")
                .listRowBackground(Paper.background)
            }
        } header: {
            CapsLabel("Favourite pens")
        } footer: {
            Text("Up to 4, in the toolbar under the colours: one tap takes the tool, colour and width. The star there adds the pen in use; hold a favourite to remove it.")
                .font(.inter(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Paper.secondary)
        }
    }

    // MARK: Toolbar

    private var toolbarSection: some View {
        Section {
            ForEach(InkTool.allCases, id: \.self) { tool in
                Toggle(isOn: Binding(
                    get: { settings.settings.toolbarTools.contains(tool) },
                    set: { shown in
                        var tools = settings.settings.toolbarTools.filter { $0 != tool }
                        if shown { tools.append(tool) }
                        settings.setToolbarTools(tools)
                    }
                )) {
                    Label {
                        InkToolbarOverlay.name(of: tool)
                    } icon: {
                        Image(systemName: InkToolbarOverlay.symbol(for: tool, eraserMode: .partial))
                    }
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Paper.ink)
                }
                .tint(Paper.ink)
                .accessibilityIdentifier("pens.show.\(tool.rawValue)")
                .listRowBackground(Paper.background)
            }
            Picker(selection: Binding(get: { ink.toolbarSide }, set: { ink.moveToolbar(to: $0) })) {
                Text("Left").tag(ToolbarSide.leading)
                Text("Right").tag(ToolbarSide.trailing)
            } label: {
                Text("Side")
                    .font(.inter(.regular, size: 17, relativeTo: .body))
                    .foregroundStyle(Paper.ink)
            }
            .accessibilityIdentifier("pens.side")
            .listRowBackground(Paper.background)
        } header: {
            CapsLabel("Toolbar")
        } footer: {
            Text("The tools the toolbar shows (at least one that writes), and the side of the page it is on. You can also drag it by its handle.")
                .font(.inter(.regular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Paper.secondary)
        }
    }
}

/// One width of a tool: its name, a slider, and a line that thick.
private struct WidthRow: View {
    let name: Text
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    let isHighlighter: Bool

    var body: some View {
        HStack(spacing: 14) {
            name
                .font(.inter(.regular, size: 15, relativeTo: .subheadline))
                .foregroundStyle(Paper.ink)
                .frame(width: 78, alignment: .leading)
            Slider(value: $width, in: range)
                .tint(Paper.ink)
            // About as thick as on the page of a 13-inch iPad.
            Capsule()
                .fill(Paper.ink.opacity(isHighlighter ? 0.35 : 1))
                .frame(width: 44, height: max(1, min(width * 0.9, 44)))
                .frame(width: 48, height: 46)
        }
    }
}

// MARK: - Paper

/// Settings → Paper: the paper of new journal pages and its spacing, how strong the
/// printed lines are, and dark paper, with the pages shown as they will look.
struct PaperSettingsView: View {
    let settings: SettingsBook
    @State private var confirmReset = false

    var body: some View {
        let paper = settings.settings.paper
        List {
            Section {
                PaperPreview(paper: paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .listRowBackground(Paper.fill)
            }

            Section {
                HStack(spacing: 14) {
                    ForEach(PaperStyle.allCases, id: \.self) { style in
                        PaperChoice(style: style, isSelected: paper.journalPaper == style) {
                            change { $0.journalPaper = style }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Paper.background)
                if paper.journalPaper != .blank {
                    SpacingPicker(spacing: Binding(get: { paper.spacing }, set: { value in change { $0.spacing = value } }))
                        .listRowBackground(Paper.background)
                }
            } header: {
                CapsLabel("New journal pages")
            } footer: {
                Text("Each page keeps its own paper; you can change it from the page too.")
                    .font(.inter(.regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Paper.secondary)
            }

            Section {
                Picker(selection: Binding(get: { paper.lineStrength }, set: { value in change { $0.lineStrength = value } })) {
                    Text("Faint").tag(LineStrength.faint)
                    Text("Normal").tag(LineStrength.normal)
                    Text("Strong").tag(LineStrength.strong)
                } label: {
                    Text("Lines")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("paper.lineStrength")
                .listRowBackground(Paper.background)
                Toggle(isOn: Binding(get: { paper.dark }, set: { value in change { $0.dark = value } })) {
                    Text("Dark paper")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                }
                .tint(Paper.ink)
                .accessibilityIdentifier("paper.dark")
                .listRowBackground(Paper.background)
            } header: {
                CapsLabel("Every page")
            } footer: {
                Text("Dark paper is black with white lines; black ink shows white on it. Shared pages and PDFs stay on white paper.")
                    .font(.inter(.regular, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Paper.secondary)
            }

            Section {
                Button {
                    confirmReset = true
                } label: {
                    Text("Reset paper")
                        .font(.inter(.regular, size: 17, relativeTo: .body))
                        .foregroundStyle(Paper.ink)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("paper.reset")
                .listRowBackground(Paper.background)
            }
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
        .scrollContentBackground(.hidden)
        .background(Paper.fill)
        .navigationTitle(Text("Paper"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(Text("Reset paper?"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button {
                settings.reset([.paper])
            } label: {
                Text("Reset")
            }
            .accessibilityIdentifier("paper.confirmReset")
            Button(role: .cancel) {} label: { Text("Cancel") }
        } message: {
            Text("White paper, normal lines, and lined paper for new journal pages.")
        }
    }

    private func change(_ edit: (inout PaperSettings) -> Void) {
        var paper = settings.settings.paper
        edit(&paper)
        settings.setPaper(paper)
    }
}

/// This month's page and a new journal page, as they will look.
private struct PaperPreview: View {
    let paper: PaperSettings

    var body: some View {
        let locale = AppLocale.current
        let today = PlannerDate(date: AppClock.now, calendar: PlannerLocale.calendar(locale: locale))
        let month = MonthPageTemplate.make(
            month: today.yearMonth, locale: locale, labels: PlannerPageContent.labels, today: today
        )
        let heading = JournalHeading.texts(title: "", date: today, locale: locale)
        let journal = JournalPageTemplate.make(
            paper: paper.journalPaper, spacing: paper.spacing, label: heading.label, heading: heading.heading
        )
        let look = TemplateLook(dark: paper.dark, lineStrength: paper.lineStrength)
        HStack(spacing: 16) {
            PageThumbnail(template: month, look: look)
            PageThumbnail(template: journal, look: look)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview of the pages"))
        .accessibilityIdentifier("paper.preview")
    }
}

/// A printed page, small, drawn by the same renderer as the pages.
struct PageThumbnail: View {
    let template: PageTemplate
    let look: TemplateLook
    var width: CGFloat = 150

    var body: some View {
        Image(uiImage: Self.image(template, look: look, width: width))
            .resizable()
            .frame(width: width, height: width * PageCanvas.size.height / PageCanvas.size.width)
            .overlay(Rectangle().stroke(Paper.hairline, lineWidth: 1))
    }

    static func image(_ template: PageTemplate, look: TemplateLook, width: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: width * PageCanvas.size.height / PageCanvas.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            TemplateRenderer.drawPage(template, in: context.cgContext, scale: width / PageCanvas.size.width, look: look)
        }
    }
}

// MARK: - Lock

/// Settings → Lock: off, the whole app, or only the journal and sketches, with Face ID,
/// Touch ID or the passcode. Turning it on asks for them first, so that it surely works.
struct LockSection: View {
    let settings: SettingsBook
    let lock: AppLock
    @State private var asking = false

    var body: some View {
        let available = AppLock.isAvailable
        Section {
            Picker(selection: Binding(get: { settings.settings.lock }, set: choose)) {
                Text("No lock").tag(LockMode.off)
                Text("Whole app").tag(LockMode.app)
                Text("Journal and sketches").tag(LockMode.journal)
            } label: {
                methodName
            }
            .pickerStyle(.inline)
            .font(.inter(.regular, size: 17, relativeTo: .body))
            .foregroundStyle(Paper.ink)
            .disabled(!available || asking)
            .accessibilityIdentifier("settings.lock")
            .listRowBackground(Paper.background)
        } header: {
            CapsLabel("Lock")
        } footer: {
            Group {
                if available {
                    Text("Asked for when the app opens and each time you come back to it. While the app is not in front, a blank page hides what is locked.")
                } else {
                    Text("To lock the app, first set a passcode for this device in the Settings app.")
                }
            }
            .font(.inter(.regular, size: 13, relativeTo: .footnote))
            .foregroundStyle(Paper.secondary)
        }
    }

    private var methodName: Text {
        switch AppLock.method {
        case .faceID: Text("Lock with Face ID")
        case .touchID: Text("Lock with Touch ID")
        case .passcode: Text("Lock with the passcode")
        }
    }

    private func choose(_ mode: LockMode) {
        guard mode != settings.settings.lock else { return }
        guard mode != .off else {
            settings.setLock(.off)
            return
        }
        asking = true
        Task {
            let reason = String(localized: "Turn on the lock", comment: "Face ID / passcode reason: turning the lock on in Settings.")
            if await lock.authenticate(reason: reason) {
                settings.setLock(mode)
            }
            asking = false
        }
    }
}
