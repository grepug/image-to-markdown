import SwiftAI

struct FormatOCRTextCompletion: AILLMCompletion {
    struct Input: AITaskInput {
        var text: String
    }

    var input: Input

    static var kind: String {
        "FormatOCRText"
    }

    var key: String {
        Self.kind
    }

    typealias Output = String

    init(input: Input) {
        self.input = input
    }

    func makeOutput(string: String) -> String {
        string
            .replacingOccurrences(of: "```markdown", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
