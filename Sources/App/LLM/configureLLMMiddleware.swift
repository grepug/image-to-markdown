import SwiftAI
import SwiftAIServer
import SwiftAIVapor
import Vapor

struct PromptTemplateProvider: AIPromptTemplateProvider {
    func promptTemplate(forKey key: String) async throws -> String {
        """
        Make the following text which is ocred from the image better in format, \
        don't change the content itself!!! \
        and remove something like the date which seems like a footer at end of the text: \
        (only output the formatted text, no other information)

        text: {{text}}
        """
    }
}

typealias CompletionClient = AICompletionClient<AIClient, PromptTemplateProvider>

struct AIRunnerStorageKey: StorageKey {
    typealias Value = CompletionClient
}

extension Request {
    var aiCompletion: CompletionClient {
        self.storage[AIRunnerStorageKey.self]!
    }
}

func configureAIMiddleware(_ app: Application) throws {
    let middleware = AIRunnerMiddleware(
        models: [
            SiliconFlow(
                apiKey: Environment.get("SiliconFlow_API_KEY")!,
                name: .deepSeek_2_5
            )
        ]
    ) { req, runner in
        req.storage[AIRunnerStorageKey.self] = runner
    } log: { string, req in
        req.logger.info("\(string)")
    }

    app.middleware.use(middleware)
}
