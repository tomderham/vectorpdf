// Assembles AppIcon.icns directly from a .iconset folder's PNGs without external dependencies.
//
// Formats standard icns chunks [4-byte OSType][4-byte big-endian length][raw PNG data]
// matching the standard 10-entry iconset mapping.
//
// Usage: swift build_icns.swift <iconset dir> <output.icns>

import Foundation

let entries: [(type: String, filename: String)] = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

guard CommandLine.arguments.count > 2 else {
    print("Usage: swift build_icns.swift <iconset dir> <output.icns>")
    exit(1)
}

let iconsetDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
}

var body: [UInt8] = []
for entry in entries {
    let fileURL = iconsetDir.appendingPathComponent(entry.filename)
    guard let data = try? Data(contentsOf: fileURL) else {
        print("Missing \(entry.filename) in \(iconsetDir.path)")
        exit(1)
    }
    let typeCode = Array(entry.type.utf8)
    precondition(typeCode.count == 4, "OSType code must be exactly 4 ASCII characters")
    let chunkLength = UInt32(8 + data.count)
    body.append(contentsOf: typeCode)
    body.append(contentsOf: bigEndianBytes(chunkLength))
    body.append(contentsOf: [UInt8](data))
}

let totalLength = UInt32(8 + body.count)
var fileBytes: [UInt8] = Array("icns".utf8)
fileBytes.append(contentsOf: bigEndianBytes(totalLength))
fileBytes.append(contentsOf: body)

try Data(fileBytes).write(to: outputURL)
print("Wrote \(outputURL.path) (\(fileBytes.count) bytes)")
