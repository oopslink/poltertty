// macos/Sources/Features/Agent/TokenTracker/ModelPricing.swift
import Foundation

struct ModelPricing {
    struct Price {
        let inputPerMillion: Decimal
        let outputPerMillion: Decimal
    }

    static let table: [String: Price] = [
        "claude-opus-4":     Price(inputPerMillion: 15.00, outputPerMillion: 75.00),
        "claude-sonnet-4":   Price(inputPerMillion: 3.00,  outputPerMillion: 15.00),
        "claude-sonnet-3-5": Price(inputPerMillion: 3.00,  outputPerMillion: 15.00),
        "claude-haiku-3-5":  Price(inputPerMillion: 0.80,  outputPerMillion: 4.00),
        "claude-haiku-3":    Price(inputPerMillion: 0.25,  outputPerMillion: 1.25),
        "gemini-2.0-flash":  Price(inputPerMillion: 0.10,  outputPerMillion: 0.40),
        "gemini-1.5-pro":    Price(inputPerMillion: 1.25,  outputPerMillion: 5.00),
    ]

    static func calculate(inputTokens: Int, outputTokens: Int, model: String) -> Decimal {
        let lower = model.lowercased()
        let price = table.first { lower.contains($0.key) }?.value
                 ?? Price(inputPerMillion: 3.00, outputPerMillion: 15.00)
        let inCost  = Decimal(inputTokens)  / 1_000_000 * price.inputPerMillion
        let outCost = Decimal(outputTokens) / 1_000_000 * price.outputPerMillion
        return inCost + outCost
    }
}
