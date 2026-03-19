// macos/Sources/Features/Agent/TokenTracker/TokenUsage.swift
import Foundation

struct TokenSnapshot: Codable {
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cost: Decimal
}

struct TokenUsage: Codable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cost: Decimal = 0
    var compactCount: Int = 0
    var contextUtilization: Float = 0
    var history: [TokenSnapshot] = []

    var totalTokens: Int { inputTokens + outputTokens }

    mutating func add(input: Int, output: Int, model: String) {
        inputTokens += input
        outputTokens += output
        cost += ModelPricing.calculate(inputTokens: input, outputTokens: output, model: model)
        history.append(TokenSnapshot(
            timestamp: Date(), inputTokens: inputTokens,
            outputTokens: outputTokens, cost: cost
        ))
    }
}
