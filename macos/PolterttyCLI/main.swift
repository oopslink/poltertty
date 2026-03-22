// macos/PolterttyCLI/main.swift
// TODO: 配置独立 Xcode Command Line Tool target，编译为 poltertty-cli 二进制
// 需要：1) 新建 CLI target  2) 添加本目录所有 .swift 文件  3) AgentBootstrap 部署编译产物到 ~/.poltertty/bin/
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
