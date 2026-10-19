// Renders short captions as PNG images (white bold text on a dark rounded box), for postprocess.mjs.
// ffmpeg's own text filter needs a build with FreeType, which Homebrew's ffmpeg may not have; this uses
// the Mac's text system instead and ffmpeg only lays the pictures over the video.
//   swift review-tours/textpng.swift jobs.json
// jobs.json: [{"text": "...", "out": "/path/caption.png", "size": 56, "maxWidth": 1000}]
import AppKit

struct Job: Decodable {
    let text: String
    let out: String
    let size: Double
    let maxWidth: Double
}

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
for job in try JSONDecoder().decode([Job].self, from: data) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = job.size * 0.15
    let text = NSAttributedString(string: job.text, attributes: [
        .font: NSFont.boldSystemFont(ofSize: job.size),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ])
    let pad = (job.size * 0.55).rounded()
    let bounds = text.boundingRect(with: NSSize(width: job.maxWidth - 2 * pad, height: 4000), options: [.usesLineFragmentOrigin, .usesFontLeading])
    let width = Int(ceil(bounds.width + 2 * pad))
    let height = Int(ceil(bounds.height + 2 * pad))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(white: 0, alpha: 0.74).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height), xRadius: job.size * 0.45, yRadius: job.size * 0.45).fill()
    text.draw(with: NSRect(x: pad, y: pad, width: Double(width) - 2 * pad, height: Double(height) - 2 * pad), options: [.usesLineFragmentOrigin, .usesFontLeading])
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: job.out))
}
