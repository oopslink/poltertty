// macos/Sources/PolterttyCLI/main.swift
import Foundation

let args = Array(CommandLine.arguments.dropFirst()) // 去掉可执行文件名

guard let subcommand = args.first else {
    fputs("Usage: poltertty-cli <ping|prepare-session|hook|extract-flag> [options]\n", stderr)
    exit(1)
}

let restArgs = Array(args.dropFirst())

switch subcommand {
case "ping":
    PingCommand.run(restArgs)
case "prepare-session":
    PrepareSessionCommand.run(restArgs)
case "hook":
    HookCommand.run(restArgs)
case "extract-flag":
    ExtractFlagCommand.run(restArgs)
default:
    fputs("Unknown subcommand: \(subcommand)\n", stderr)
    exit(1)
}
