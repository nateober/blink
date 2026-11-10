//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// ImagePaste: send an image from the clipboard to a fleet host over SSH and hand back the
// text to type (the file's path), so a coding agent there can look at a screenshot taken
// on the phone. What is sent and where it lands is decided in FleetCore/PasteUpload.
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import UIKit

enum ImagePaste {
  struct Failure: Error {
    let message: String
  }

  /// The image as a JPEG no larger than `PasteUpload.maxSide` on its longest side.
  static func jpeg(from image: UIImage) -> Data? {
    let pixels = (width: Double(image.size.width * image.scale), height: Double(image.size.height * image.scale))
    let target = PasteUpload.scaledSize(width: pixels.width, height: pixels.height)
    guard target.width >= 1, target.height >= 1 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let size = CGSize(width: target.width, height: target.height)
    let scaled = UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    return scaled.jpegData(compressionQuality: 0.85)
  }

  /// Uploads the image and returns the text to type at the cursor.
  static func send(_ image: UIImage, alias: String) async -> Result<String, Failure> {
    guard let data = jpeg(from: image) else {
      return .failure(Failure(message: "the image could not be read"))
    }
    let name = PasteUpload.fileName(at: Date())
    let commands = PasteUpload.commands(base64: data.base64EncodedString(), fileName: name)
    var lastOutput = ""
    for command in commands {
      do {
        let result = try await HeadlessSSHRunner.run(alias: alias, command: command, overallTimeout: 45)
        guard result.exitOK else {
          let why = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
          return .failure(Failure(message: why.isEmpty ? "the host refused the file" : why))
        }
        lastOutput = result.stdout
      } catch {
        return .failure(Failure(message: (error as? LocalizedError)?.errorDescription ?? "\(error)"))
      }
    }
    guard let typed = PasteUpload.typedText(stdout: lastOutput, fileName: name) else {
      return .failure(Failure(message: "the host did not confirm the file"))
    }
    return .success(typed)
  }
}
