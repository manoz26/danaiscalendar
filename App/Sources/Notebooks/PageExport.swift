import PencilKit
import PlannerCore
import UIKit

enum PageExportFormat {
    case pdf, image
}

/// A page as a PDF or an image, printed template and ink together, to share.
@MainActor
enum PageExporter {
    /// PDF page width in points: A4 (the page is a little shorter, 1000 x 1400).
    static let pdfWidth: CGFloat = 595.28

    #if DEBUG
    /// The last exported file and its size, for the UI tests ("debug.lastExport").
    static var lastExport = ""
    #endif

    /// Writes the page to a new file in the temporary folder and returns it. The previous
    /// exports are removed first.
    static func export(
        template: PageTemplate, drawing: PKDrawing, name: String, format: PageExportFormat
    ) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        let unique = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unique, withIntermediateDirectories: true)

        let data: Data
        let url: URL
        switch format {
        case .pdf:
            data = pdf(template: template, drawing: drawing, title: name)
            url = unique.appending(path: "\(fileName(name)).pdf")
        case .image:
            data = image(template: template, drawing: drawing, scale: 2).pngData() ?? Data()
            url = unique.appending(path: "\(fileName(name)).png")
        }
        try data.write(to: url, options: .atomic)
        AppLog.info("Exported a page as \(format == .pdf ? "PDF" : "image") (\(data.count / 1024) KB)")
        #if DEBUG
        lastExport = "\(url.pathExtension) \(data.count)"
        #endif
        return url
    }

    /// One PDF page: the template as vectors (sharp text and lines), the ink on top.
    static func pdf(template: PageTemplate, drawing: PKDrawing, title: String) -> Data {
        let size = CGSize(width: pdfWidth, height: pdfWidth * PageCanvas.aspectRatio)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "Danai's Calendar",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size), format: format)
        let ink = inkImage(drawing, scale: 2)
        return renderer.pdfData { context in
            context.beginPage()
            TemplateRenderer.drawPage(template, in: context.cgContext, scale: size.width / PageCanvas.size.width)
            ink?.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// The page as a picture, `scale` pixels per canvas unit.
    static func image(template: PageTemplate, drawing: PKDrawing, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let ink = inkImage(drawing, scale: scale)
        return UIGraphicsImageRenderer(size: PageCanvas.size, format: format).image { context in
            TemplateRenderer.drawPage(template, in: context.cgContext, scale: 1)
            ink?.draw(in: CGRect(origin: .zero, size: PageCanvas.size))
        }
    }

    /// The ink of the whole page as a transparent picture, always in light colours (in dark
    /// mode PencilKit would turn black ink white).
    static func inkImage(_ drawing: PKDrawing, scale: CGFloat) -> UIImage? {
        guard !drawing.strokes.isEmpty else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: CGRect(origin: .zero, size: PageCanvas.size), scale: scale)
        }
        return image
    }

    /// A file name without characters that file systems refuse.
    static func fileName(_ name: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Danai's Calendar" : String(cleaned.prefix(80))
    }
}

/// The system share sheet for a file: as a popover under the top bar's right end on
/// iPad, from the bottom on iPhone.
@MainActor
enum SharePresenter {
    static func present(_ url: URL) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
              var top = window.rootViewController else {
            AppLog.warning("No window to share from")
            return
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.maxX - 150, y: window.safeAreaInsets.top + 8, width: 44, height: 36)
            popover.permittedArrowDirections = [.up]
        }
        top.present(activity, animated: true)
    }
}

/// Small pictures of pages (template and ink) for the journal's and the sketches' grids.
/// Kept while the grid is open; a new grid draws them again, so they are never stale.
@MainActor
final class PageThumbnails {
    /// Points per canvas unit: a page 200 points wide.
    static let scale: CGFloat = 0.2

    private var cache: [PlannerPage: UIImage] = [:]
    private let ink: InkController

    init(ink: InkController) {
        self.ink = ink
    }

    func image(for content: PlannerPageContent) -> UIImage {
        if let image = cache[content.page] {
            return image
        }
        let image = Self.render(template: content.template, drawing: ink.drawing(of: content.page))
        cache[content.page] = image
        return image
    }

    static func render(template: PageTemplate, drawing: PKDrawing) -> UIImage {
        let size = CGSize(width: PageCanvas.size.width * scale, height: PageCanvas.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let pixels = scale * format.scale
        let ink = PageExporter.inkImage(drawing, scale: pixels)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            TemplateRenderer.drawPage(template, in: context.cgContext, scale: scale)
            ink?.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
