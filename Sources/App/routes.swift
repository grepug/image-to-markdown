import Vapor

func routes(_ app: Application) throws {
    app.routes.defaultMaxBodySize = "10mb"

    app.get { req async throws -> View in
        return try await req.view.render("index", ["name": "Leaf"])
    }

    try app.register(collection: MainController())
}
