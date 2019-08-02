import XCTest

import SwiftSMTPTests
import SwiftSMTPVaporTests

var tests = [XCTestCaseEntry]()
tests += SwiftSMTPTests.__allTests()
tests += SwiftSMTPVaporTests.__allTests()

XCTMain(tests)
