import Foundation

public struct SponsorPromptState: Codable, Equatable {
    public var successfulApplyCount: Int
    public var lastPromptedAtCount: Int?
    public var isDisabled: Bool

    public init(
        successfulApplyCount: Int = 0,
        lastPromptedAtCount: Int? = nil,
        isDisabled: Bool = false
    ) {
        self.successfulApplyCount = successfulApplyCount
        self.lastPromptedAtCount = lastPromptedAtCount
        self.isDisabled = isDisabled
    }
}

public enum SponsorPromptPolicy {
    public static let firstPromptThreshold = 3
    public static let repeatInterval = 10

    public static func recordSuccessfulApply(_ state: inout SponsorPromptState) {
        state.successfulApplyCount += 1
    }

    public static func recordPromptShown(_ state: inout SponsorPromptState) {
        state.lastPromptedAtCount = state.successfulApplyCount
    }

    public static func disable(_ state: inout SponsorPromptState) {
        state.isDisabled = true
    }

    public static func shouldPrompt(_ state: SponsorPromptState) -> Bool {
        guard !state.isDisabled else { return false }
        guard let lastPromptedAtCount = state.lastPromptedAtCount else {
            return state.successfulApplyCount >= firstPromptThreshold
        }
        return state.successfulApplyCount >= lastPromptedAtCount + repeatInterval
    }
}
