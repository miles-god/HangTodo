// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HangTodo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "HangTodo", path: "Sources/Tendedero"),
        .testTarget(name: "HangTodoTests", dependencies: ["HangTodo"])
    ]
)
