import XCTest
@testable import TunnelDetourCore

final class SponsorPromptPolicyTests: XCTestCase {
    func testFirstPromptRequiresThreeSuccessfulApplies() {
        var state = SponsorPromptState()
        XCTAssertFalse(SponsorPromptPolicy.shouldPrompt(state))
        SponsorPromptPolicy.recordSuccessfulApply(&state)
        SponsorPromptPolicy.recordSuccessfulApply(&state)
        XCTAssertFalse(SponsorPromptPolicy.shouldPrompt(state))
        SponsorPromptPolicy.recordSuccessfulApply(&state)
        XCTAssertTrue(SponsorPromptPolicy.shouldPrompt(state))
    }

    func testMaybeLaterWaitsForTenMoreSuccessfulApplies() {
        var state = SponsorPromptState(successfulApplyCount: 3)
        SponsorPromptPolicy.recordPromptShown(&state)
        for _ in 0..<9 {
            SponsorPromptPolicy.recordSuccessfulApply(&state)
        }
        XCTAssertFalse(SponsorPromptPolicy.shouldPrompt(state))
        SponsorPromptPolicy.recordSuccessfulApply(&state)
        XCTAssertTrue(SponsorPromptPolicy.shouldPrompt(state))
    }

    func testDisabledPromptNeverReturns() {
        var state = SponsorPromptState(successfulApplyCount: 100)
        SponsorPromptPolicy.disable(&state)
        XCTAssertFalse(SponsorPromptPolicy.shouldPrompt(state))
    }
}
