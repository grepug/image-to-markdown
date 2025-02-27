import Vapor

struct MainController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("upload", use: index)
    }

    @Sendable
    func index(req: Request) async throws -> View {
        struct Input: Content {
            var images: [File]
        }

        let input = try req.content.decode(Input.self)
        let orderedFiles = input.images.sorted { $0.filename < $1.filename }

        typealias Detail = ApiResponse.Result.Detail

        let blocks: [String] = try await withThrowingTaskGroup(of: (String, Int).self) { group in
            for (index, file) in orderedFiles.enumerated() {
                group.addTask {
                    let details = try await getImageDetail(file: file, req: req)
                    let text = try await extractText(from: details, req: req)

                    return (text, index)
                }

            }

            let res: [(String, Int)] = try await group.reduce(into: []) { partialResult, item in
                partialResult.append(item)
            }

            return res.sorted { $0.1 < $1.1 }.map { $0.0 }
        }

        let markdown = blocks.joined(separator: "\n")
            // replace only \n to \n\n
            .replacingOccurrences(of: "\n(?!\n)", with: "\n\n", options: .regularExpression)
            // replace more than 2 \n to 2 \n
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        print("Markdown: \(markdown)")

        return try await req.view.render("result", ["markdown": markdown])
    }

    func getImageDetail(file: File, req: Request) async throws -> [ApiResponse.Result.Detail] {
        let fileData = Data(buffer: file.data)

        let appId = Environment.get("x-ti-app-id")!
        let appKey = Environment.get("x-ti-secret-code")!

        let response = try await req.client.post("https://api.textin.com/ai/service/v1/pdf_to_markdown") { req in
            req.headers.add(name: "x-ti-app-id", value: appId)
            req.headers.add(name: "x-ti-secret-code", value: appKey)
            req.headers.contentType = .binary
            req.body = .init(data: fileData)
        }

        let res = try response.content.decode(ApiResponse.self)
        return res.result.detail
    }

    func extractText(from detail: [ApiResponse.Result.Detail], req: Request) async throws -> String {
        var text = ""
        var firstBlockPos: Int?

        for item in detail {
            if item.sub_type?.discardable ?? true {
                continue
            }

            let pos = item.position.first ?? 0

            guard pos < 100 else {
                continue
            }

            if firstBlockPos == nil {
                firstBlockPos = pos
            }

            // pos must be between firstBlockPos +- 10
            if let firstBlockPos = firstBlockPos, abs(firstBlockPos - pos) > 10 {
                continue
            }

            if item.sub_type == .text_title {
                text += "## \(item.text)\n\n"
            } else {
                text += item.text + "\n\n"
            }
        }

        let completion = FormatOCRTextCompletion(input: .init(text: text))
        let res = try await req.aiCompletion.generate(completion: completion)

        return res
    }
}

struct ApiResponse: Content {
    struct Result: Content {
        var markdown: String
        var success_count: Int
        // var pages: [Page]
        var detail: [Detail]

        struct Page: Content {
            var angle: Int
            var page_id: Int
            var content: [ContentItem]
            var status: String
            var height: Int
            var structured: [StructuredItem]
            var durations: Double
            var image_id: String
            var width: Int

            struct ContentItem: Content {
                var pos: [Int]
                var id: Int
                var score: Double
                var type: String
                var text: String
            }

            struct StructuredItem: Content {
                var pos: [Int]
                var type: String
                var id: Int?
                var content: [Int]?
                var text: String?
                var outline_level: Int?
                var sub_type: String?
            }
        }

        struct Detail: Content {
            enum SubType: String, Content {
                case text_title, text, footer, header

                var discardable: Bool {
                    self == .footer || self == .header
                }
            }

            var paragraph_id: Int
            var page_id: Int
            var tags: [String]?
            var outline_level: Int
            var text: String
            var type: String
            var position: [Int]
            var content: Int
            var sub_type: SubType?
        }
    }

    var duration: Int
    var message: String
    var result: Result
}
