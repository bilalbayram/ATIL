import Foundation
import Testing
@testable import ATIL

struct LaunchdScannerTests {
    let scanner = LaunchdScanner()

    @Test func scanReturnsResults() {
        let map = scanner.scanAll()
        // There should be at least some launchd plists on any macOS system
        #expect(!map.isEmpty, "Should find at least one launchd plist")
    }

    @Test func searchDirectoriesExist() {
        let fm = FileManager.default
        // At least /Library/LaunchDaemons should exist on macOS
        #expect(fm.fileExists(atPath: "/Library/LaunchDaemons"))
    }

    @Test func scannedJobsHaveLabels() {
        let map = scanner.scanAll()
        for (_, job) in map {
            #expect(!job.label.isEmpty, "Every launchd job should have a label")
            #expect(!job.plistPath.isEmpty, "Every job should have a plist path")
        }
    }
}
