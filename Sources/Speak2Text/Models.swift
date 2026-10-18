import Foundation

struct ModelInfo: Identifiable, Equatable {
    let id: String          // WhisperKit variant folder name
    let title: String
    let sizeMB: Int
}

enum ModelCatalog {
    static let defaultID = "openai_whisper-large-v3-v20240930_turbo_632MB"
    static let all: [ModelInfo] = [
        ModelInfo(id: defaultID, title: "Large v3 turbo", sizeMB: 632),
        ModelInfo(id: "openai_whisper-large-v3-v20240930_626MB", title: "Large v3", sizeMB: 626),
        ModelInfo(id: "openai_whisper-small_216MB", title: "Small", sizeMB: 216),
        ModelInfo(id: "openai_whisper-base", title: "Base", sizeMB: 140),
    ]

    /// Folders where a downloaded model may live, in search order.
    static var searchRoots: [String] {
        [Paths.home + "/Documents/huggingface/models/argmaxinc/whisperkit-coreml",
         Paths.downloadBase + "/models/argmaxinc/whisperkit-coreml"]
    }

    /// Local folder of a model, or nil if it is not downloaded yet.
    static func folder(for id: String) -> String? {
        for r in searchRoots {
            let p = r + "/" + id
            if FileManager.default.fileExists(atPath: p + "/AudioEncoder.mlmodelc") { return p }
        }
        return nil
    }
}
