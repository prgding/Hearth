//
//  HearthTests.swift
//  HearthTests
//
//  Created by dingshuai on 5/25/26.
//

import Testing
@testable import Hearth

struct HearthTests {

    @Test func parsesSinaUSDCNYRate() throws {
        let raw = #"var hq_str_fx_susdcny="16:01:00,6.6790000000,6.6791000000,6.6810000000";"#
        let rate = try SinaQuoteProvider().parseUSDCNYRate(raw)
        #expect(rate == 6.679)
    }

}
