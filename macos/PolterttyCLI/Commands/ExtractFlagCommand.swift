// macos/Sources/PolterttyCLI/Commands/ExtractFlagCommand.swift
import Foundation

enum ExtractFlagCommand {
    static func run(_ args: [String]) {
        guard let flag = args.first else {
            fputs("Error: flag name is required as the first argument\n", stderr)
            exit(1)
        }

        let searchArgs = Array(args.dropFirst())

        if let value = extractArg(flag, from: searchArgs) {
            print(value)
            exit(0)
        } else {
            exit(1)
        }
    }
}
