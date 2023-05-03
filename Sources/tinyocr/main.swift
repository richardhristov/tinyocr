import ArgumentParser
import Cocoa
import Vision
import Foundation
import PDFKit

@available(macOS 11.0, *)

struct tinyocr: ArgumentParser.ParsableCommand {
    public static let configuration = CommandConfiguration(abstract: "Perform OCR on every image passed a command line argument, output to stdout")

    @Option
    var lang: [String] = ["en"]

    @Option(help: "Custom word list from file",
            completion: .file(extensions: ["txt"]))
    var words: String?

    @Argument(completion: .file(extensions: ["jpeg","jpg","png","tiff","pdf"])) // support more?
    var files: [String] = []

    mutating func run() throws {
        // build the request handler and perform the request
        let request = VNRecognizeTextRequest { (request, error) in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            // take the most likely result for each chunk, then send them all the stdout
            let obs : [String] = observations.map { $0.topCandidates(1).first?.string ?? ""}
            print(obs.joined(separator: "\n"))
        }
        request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision2
        if #available(macOS 13.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        request.recognitionLanguages = lang
        if words != nil {
            let text = try String(contentsOfFile: words!)
            request.customWords = text.components(separatedBy: "\n")
        }
        for url in files.map({ URL(fileURLWithPath: $0) }) {
            if url.pathExtension.lowercased() == "pdf" {
                guard let pdfDocument = PDFDocument(url: url) else {
                    fatalError("Error: could not open PDF document - '\(url)'")
                }
                for pageIndex in 0..<pdfDocument.pageCount {
                    guard let pdfPage = pdfDocument.page(at: pageIndex) else {
                        fatalError("Error: could not get page \(pageIndex) from PDF document - '\(url)'")
                    }
                    let pageRect = pdfPage.bounds(for: .mediaBox)
                    let scaleFactor: CGFloat = 4.0
                    let thumbnailSize = CGSize(width: pageRect.width * scaleFactor, height: pageRect.height * scaleFactor)
                    let thumbnail = pdfPage.thumbnail(of: thumbnailSize, for: .mediaBox)
                    guard let imgRef = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        fatalError("Error: could not convert NSImage to CGImage - '\(url)'")
                    }
                    let destinationURL = url.deletingPathExtension().appendingPathExtension("\(pageIndex).png")
                    guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, kUTTypePNG, 1, nil) else { fatalError(
                        "Error: could not create CGImageDestination for '\(destinationURL)'") }
                    CGImageDestinationAddImage(destination, imgRef, nil)
                    CGImageDestinationFinalize(destination)
                    try? VNImageRequestHandler(cgImage: imgRef, options: [:]).perform([request])
                }
            } else {
                guard let imgRef = NSImage(byReferencing: url).cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    fatalError("Error: could not convert NSImage to CGImage - '\(url)'")
                }
                try? VNImageRequestHandler(cgImage: imgRef, options: [:]).perform([request])
            }
        }
    }
}

if #available(macOS 11.0, *) {
    tinyocr.main()
} else {
    print("This code only runs on macOS 11.0 and higher")
}
