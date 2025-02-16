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
        let client = req.client

        let appId = Environment.get("x-ti-app-id")!
        let appKey = Environment.get("x-ti-secret-code")!

        var blocks: [String] = []
        var firstBlockPos: Int?

        for file in orderedFiles {
            let fileData = Data(buffer: file.data)
            let response = try await client.post("https://api.textin.com/ai/service/v1/pdf_to_markdown") { req in
                req.headers.add(name: "x-ti-app-id", value: appId)
                req.headers.add(name: "x-ti-secret-code", value: appKey)
                req.headers.contentType = .binary
                req.body = .init(data: fileData)
            }

            let res = try response.content.decode(ApiResponse.self)
            let items: [ApiResponse.Result.Detail] = res.result.detail.reduce(into: []) { partialResult, item in
                if item.sub_type.discardable {
                    return
                }

                let pos = item.position.first ?? 0

                if firstBlockPos == nil {
                    firstBlockPos = pos
                }

                // pos must be between firstBlockPos +- 10
                if let firstBlockPos = firstBlockPos, abs(firstBlockPos - pos) > 10 {
                    return
                }

                partialResult.append(item)
            }

            let newBlocks = try await withThrowingTaskGroup(of: (String, Int).self) { group in
                for (index, item) in items.enumerated() {
                    group.addTask {
                        let res = try await req.aiCompletion.generate(
                            completion: FormatOCRTextCompletion(
                                input: .init(text: item.text)
                            )
                        )

                        if item.sub_type == .text_title {
                            return ("## \(res)", index)
                        } else {
                            return (res, index)
                        }
                    }
                }

                let res: [(String, Int)] = try await group.reduce(into: []) { partialResult, item in
                    partialResult.append(item)
                }

                return res.sorted { $0.1 < $1.1 }.map { $0.0 }
            }

            blocks.append(contentsOf: newBlocks)
        }

        let markdown = blocks.joined(separator: "\n\n")

        print("Markdown: \(markdown)")

        return try await req.view.render("result", ["markdown": markdown])
    }
}

struct ApiResponse: Content {
    struct Result: Content {
        var markdown: String
        var success_count: Int
        var pages: [Page]
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
            var tags: [String]
            var outline_level: Int
            var text: String
            var type: String
            var position: [Int]
            var content: Int
            var sub_type: SubType
        }
    }

    var duration: Int
    var message: String
    var result: Result
}
