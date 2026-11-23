import Foundation
import OmnixCoreC

enum SmokeError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(text): return text
        }
    }
}

func readError(_ error: inout UnsafeMutablePointer<CChar>?) -> SmokeError {
    guard let pointer = error else { return .message("Omnix Core returned an error.") }
    defer {
        omnix_string_free(pointer)
        error = nil
    }
    return .message(String(cString: pointer))
}

func asPart(_ bytes: UnsafeRawBufferPointer, _ kind: UInt32) -> OmnixPart {
    OmnixPart(kind: kind, data: bytes.bindMemory(to: UInt8.self).baseAddress, size: bytes.count)
}

func send(_ conversation: OpaquePointer, question: String, images: (Data, Data)? = nil) throws {
    guard let cancel = omnix_cancellation_new() else {
        throw SmokeError.message("Could not create a cancellation handle.")
    }
    defer { omnix_cancellation_free(cancel) }
    var error: UnsafeMutablePointer<CChar>?
    let text = Data(question.utf8)
    let status = text.withUnsafeBytes { prompt in
        func sendParts(_ parts: [OmnixPart]) -> Int32 {
            parts.withUnsafeBufferPointer { parts in
                omnix_conversation_send(conversation, parts.baseAddress, parts.count, cancel, {
                    _, text, size in
                    guard let text else { return false }
                    FileHandle.standardOutput.write(Data(bytes: text, count: size))
                    return true
                }, nil, &error)
            }
        }
        if let (overview, crop) = images {
            return overview.withUnsafeBytes { first in
                crop.withUnsafeBytes { second in
                    sendParts([asPart(first, UInt32(OMNIX_IMAGE)), asPart(second, UInt32(OMNIX_IMAGE)),
                               asPart(prompt, UInt32(OMNIX_TEXT))])
                }
            }
        }
        return sendParts([asPart(prompt, UInt32(OMNIX_TEXT))])
    }
    guard status == Int32(OMNIX_COMPLETED) else { throw readError(&error) }
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func main(_ args: [String]) throws {
    if args.count == 2 && args[1] == "--check-linkage" {
        // A missing file must reach artifact validation
        // through the Swift bridge and the actual sibling runtime loader.
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".litertlm")
        var error: UnsafeMutablePointer<CChar>?
        if let model = omnix_model_open(fixture.path, nil, 4096, true, false, &error) {
            omnix_model_close(model)
            throw SmokeError.message("A missing artifact unexpectedly opened.")
        }
        let result = readError(&error).localizedDescription
        guard result == "An absolute model file path is required" else {
            throw SmokeError.message(result)
        }
        print("Swift loaded Omnix Core and LiteRT-LM and reached model validation.")
        return
    }
    guard args.count == 6 else {
        throw SmokeError.message("Usage: omnix-core-smoke MODEL OVERVIEW CROP QUESTION FOLLOW_UP")
    }
    let modelURL = URL(fileURLWithPath: args[1]).standardizedFileURL
    let overview = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let crop = try Data(contentsOf: URL(fileURLWithPath: args[3]))
    var error: UnsafeMutablePointer<CChar>?
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("omnix-swift-smoke-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: cache) }
    guard let model = omnix_model_open(modelURL.path, cache.path, 4096, true, false, &error) else {
        throw readError(&error)
    }
    defer { omnix_model_close(model) }
    guard let conversation = omnix_conversation_open(model, "Answer briefly using the supplied images.", 64, &error) else {
        throw readError(&error)
    }
    defer { omnix_conversation_close(conversation) }
    try send(conversation, question: args[4], images: (overview, crop))
    try send(conversation, question: args[5])
}

do {
    try main(CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
