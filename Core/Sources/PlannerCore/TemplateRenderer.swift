import CoreGraphics
import CoreText
import Foundation

/// Draws a `PageTemplate` with Core Graphics and Core Text.
///
/// The same routine draws on screen (a tiled layer), into images and into PDFs. The
/// context's user space must be in canvas units with the origin at the top-left and y
/// going down, which is what UIKit, `UIGraphicsImageRenderer`, `UIGraphicsPDFRenderer`
/// and layers on iOS give; scale it first with `drawPage(_:in:scale:)` or `scaleBy`.
/// Safe to call from any thread.
public enum TemplateRenderer {
    /// Paints the paper and the template at `scale` (device units per canvas unit).
    public static func drawPage(_ template: PageTemplate, in context: CGContext, scale: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(Tone.paper.cgColor)
        context.fill(CGRect(origin: .zero, size: PageCanvas.size))
        draw(template, in: context)
    }

    /// Draws the template's shapes; the context is already in canvas units.
    public static func draw(_ template: PageTemplate, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setShouldAntialias(true)
        // Greyscale antialiasing only: subpixel (LCD) smoothing would tint the edges of text.
        context.setShouldSmoothFonts(false)
        context.setLineCap(.butt)
        let visible = context.boundingBoxOfClipPath
        for shape in template.shapes where bounds(of: shape).intersects(visible) {
            draw(shape, in: context)
        }
    }

    static func draw(_ shape: TemplateShape, in context: CGContext) {
        switch shape {
        case let .line(from, to, width, tone):
            context.setStrokeColor(tone.cgColor)
            context.setLineWidth(width)
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()

        case let .rect(rect, fill, stroke, lineWidth, cornerRadius):
            let path = cornerRadius > 0
                ? CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
                : CGPath(rect: rect, transform: nil)
            fillAndStroke(path, fill: fill, stroke: stroke, lineWidth: lineWidth, in: context)

        case let .circle(center, radius, fill, stroke, lineWidth):
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            fillAndStroke(CGPath(ellipseIn: rect, transform: nil), fill: fill, stroke: stroke, lineWidth: lineWidth, in: context)

        case let .text(text):
            draw(text, in: context)
        }
    }

    private static func fillAndStroke(_ path: CGPath, fill: Tone?, stroke: Tone?, lineWidth: CGFloat, in context: CGContext) {
        if let fill {
            context.addPath(path)
            context.setFillColor(fill.cgColor)
            context.fillPath()
        }
        if let stroke, lineWidth > 0 {
            context.addPath(path)
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(lineWidth)
            context.strokePath()
        }
    }

    // MARK: - Text

    static func draw(_ text: TemplateText, in context: CGContext) {
        let line = makeLine(text)
        let x: CGFloat = switch text.alignment {
        case .left: text.anchor.x
        case .center: text.anchor.x - width(of: line, text) / 2
        case .right: text.anchor.x - width(of: line, text)
        }
        context.saveGState()
        // The context's y axis points down; flip the glyphs so they stand upright.
        // (The text matrix is not part of the graphics state, so set it every time.)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: text.anchor.y)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Width of the printed text, without the tracking after the last letter.
    public static func width(of text: TemplateText) -> CGFloat {
        width(of: makeLine(text), text)
    }

    private static func width(of line: CTLine, _ text: TemplateText) -> CGFloat {
        let typographic = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return max(0, typographic - text.tracking)
    }

    private static func makeLine(_ text: TemplateText) -> CTLine {
        let font = CTFontCreateWithName(text.font.postScriptName as CFString, text.size, nil)
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): text.tone.cgColor,
        ]
        if text.tracking != 0 {
            attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = text.tracking
        }
        let string = NSAttributedString(string: text.string, attributes: attributes)
        return CTLineCreateWithAttributedString(string as CFAttributedString)
    }

    // MARK: - Culling

    /// A generous bounding box, used only to skip shapes outside the area being drawn.
    static func bounds(of shape: TemplateShape) -> CGRect {
        switch shape {
        case let .line(from, to, width, _):
            return CGRect(
                x: min(from.x, to.x), y: min(from.y, to.y),
                width: abs(to.x - from.x), height: abs(to.y - from.y)
            ).insetBy(dx: -width, dy: -width)
        case let .rect(rect, _, _, lineWidth, _):
            return rect.insetBy(dx: -lineWidth, dy: -lineWidth)
        case let .circle(center, radius, _, _, lineWidth):
            let r = radius + lineWidth
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        case let .text(text):
            // Upper bound: no glyph of these fonts is wider than 1 em, plus tracking.
            let width = CGFloat(text.string.count) * (text.size + text.tracking)
            let left: CGFloat = switch text.alignment {
            case .left: text.anchor.x
            case .center: text.anchor.x - width / 2
            case .right: text.anchor.x - width
            }
            return CGRect(x: left, y: text.anchor.y - text.size * 1.2, width: width, height: text.size * 1.6)
        }
    }
}

extension Tone {
    public var cgColor: CGColor {
        CGColor(gray: white, alpha: 1)
    }
}
