#!/usr/bin/env swift

// Generates the complete macOS AppIcon set for SmartPiP.
//
//   swift Scripts/generate-app-icons.swift
//       Draws self-labelling placeholders — a flat background with the file's own
//       pixel dimensions printed on it.
//
//   swift Scripts/generate-app-icons.swift --source Artwork/icon.png
//       Downscales one square source image (1024×1024 recommended) into every slot.
//       This is the path to use once real artwork exists.
//
//   --output <dir>   Write somewhere other than the default AppIcon.appiconset.
//
// Every slot listed in ICONS.md is written, along with a matching Contents.json.

import AppKit
import Foundation

// MARK: - Slot table

/// One entry in the asset catalog's AppIcon set.
struct IconSlot {
    /// Point size, as macOS names the slot ("16x16", "512x512").
    let points: Int
    /// 1 or 2.
    let scale: Int

    var pixels: Int { points * scale }

    var sizeName: String { "\(points)x\(points)" }

    var filename: String {
        scale == 1 ? "icon_\(sizeName).png" : "icon_\(sizeName)@\(scale)x.png"
    }
}

/// Every slot macOS expects for a Mac app icon: 16, 32, 128, 256 and 512 points,
/// each at @1x and @2x. Leaving any of these empty makes Xcode warn on build.
let slots: [IconSlot] = [16, 32, 128, 256, 512].flatMap { points in
    [IconSlot(points: points, scale: 1), IconSlot(points: points, scale: 2)]
}

// MARK: - Arguments

func parseArguments() -> (source: URL?, output: URL) {
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let repositoryRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    let defaultOutput = repositoryRoot
        .appendingPathComponent("SmartPiP/Assets.xcassets/AppIcon.appiconset")

    var source: URL?
    var output = defaultOutput

    var arguments = Array(CommandLine.arguments.dropFirst())
    while let flag = arguments.first {
        arguments.removeFirst()
        switch flag {
        case "--source":
            guard let path = arguments.first else { fail("--source needs a file path") }
            arguments.removeFirst()
            source = URL(fileURLWithPath: path)
        case "--output":
            guard let path = arguments.first else { fail("--output needs a directory path") }
            arguments.removeFirst()
            output = URL(fileURLWithPath: path)
        case "--help", "-h":
            print("usage: generate-app-icons.swift [--source <image>] [--output <appiconset dir>]")
            exit(0)
        default:
            fail("unknown argument: \(flag)")
        }
    }

    return (source, output)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Drawing

func makeBitmap(pixels: Int, draw: (NSSize) -> Void) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fail("could not allocate a \(pixels)×\(pixels) bitmap")
    }

    // Match the point size to the pixel size so drawing is 1:1 with pixels.
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fail("could not create a drawing context for \(pixels)×\(pixels)")
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    draw(rep.size)
    context.flushGraphics()

    return rep
}

/// Flat background plus the file's own pixel dimensions, so it is obvious at a
/// glance which file maps to which slot. Throwaway art by design.
func drawPlaceholder(slot: IconSlot, in size: NSSize) {
    let side = size.width
    let inset = (side * 0.06).rounded()
    let radius = side * 0.18

    // Hue walks with the slot so neighbouring sizes are easy to tell apart.
    let index = slots.firstIndex { $0.filename == slot.filename } ?? 0
    let hue = CGFloat(index) / CGFloat(max(slots.count, 1))
    let background = NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.78, alpha: 1)

    let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    background.setFill()
    NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius).fill()

    let primary = "\(slot.pixels)"
    let secondary = "\(slot.sizeName) @\(slot.scale)x"
    let showsSecondary = slot.pixels >= 128

    let primarySize = (side * (showsSecondary ? 0.30 : 0.42)).rounded()
    let primaryAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: primarySize, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
    let primaryBounds = (primary as NSString).size(withAttributes: primaryAttributes)

    let secondaryAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: (side * 0.10).rounded(), weight: .medium),
        .foregroundColor: NSColor(white: 1, alpha: 0.85),
    ]
    let secondaryBounds = showsSecondary
        ? (secondary as NSString).size(withAttributes: secondaryAttributes)
        : .zero

    let gap = showsSecondary ? side * 0.03 : 0
    let blockHeight = primaryBounds.height + gap + secondaryBounds.height
    var y = (side - blockHeight) / 2

    if showsSecondary {
        (secondary as NSString).draw(
            at: NSPoint(x: (side - secondaryBounds.width) / 2, y: y),
            withAttributes: secondaryAttributes)
        y += secondaryBounds.height + gap
    }

    (primary as NSString).draw(
        at: NSPoint(x: (side - primaryBounds.width) / 2, y: y),
        withAttributes: primaryAttributes)
}

func drawScaled(_ image: NSImage, in size: NSSize) {
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.draw(
        in: NSRect(origin: .zero, size: size),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high.rawValue]
    )
}

// MARK: - Contents.json

func contentsJSON() -> Data {
    let images = slots.map { slot in
        """
            {
              "filename" : "\(slot.filename)",
              "idiom" : "mac",
              "scale" : "\(slot.scale)x",
              "size" : "\(slot.sizeName)"
            }
        """
    }

    let json = """
    {
      "images" : [
    \(images.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
    return Data(json.utf8)
}

// MARK: - Main

let (sourceURL, outputURL) = parseArguments()

var sourceImage: NSImage?
if let sourceURL {
    guard let image = NSImage(contentsOf: sourceURL) else {
        fail("could not read source image at \(sourceURL.path)")
    }
    if image.size.width != image.size.height {
        FileHandle.standardError.write(
            Data("warning: source image is not square; it will be stretched\n".utf8))
    }
    sourceImage = image
}

do {
    try FileManager.default.createDirectory(
        at: outputURL, withIntermediateDirectories: true)
} catch {
    fail("could not create \(outputURL.path): \(error.localizedDescription)")
}

for slot in slots {
    let rep = makeBitmap(pixels: slot.pixels) { size in
        if let sourceImage {
            drawScaled(sourceImage, in: size)
        } else {
            drawPlaceholder(slot: slot, in: size)
        }
    }

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fail("could not encode \(slot.filename) as PNG")
    }

    let destination = outputURL.appendingPathComponent(slot.filename)
    do {
        try data.write(to: destination, options: .atomic)
    } catch {
        fail("could not write \(destination.path): \(error.localizedDescription)")
    }

    print("wrote \(slot.filename) (\(slot.pixels)×\(slot.pixels))")
}

let contentsURL = outputURL.appendingPathComponent("Contents.json")
do {
    try contentsJSON().write(to: contentsURL, options: .atomic)
} catch {
    fail("could not write \(contentsURL.path): \(error.localizedDescription)")
}

print("wrote Contents.json — \(slots.count) slots in \(outputURL.path)")
