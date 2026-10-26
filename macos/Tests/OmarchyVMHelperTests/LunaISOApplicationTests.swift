import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite("Luna ISO launch request")
struct LunaISOApplicationTests {
    @Test("An ISO path stays one process argument")
    func isoArguments() throws {
        let request = try LunaISOLaunchRequest(isoPath: "/tmp/Luna OS, preview.iso", memoryMiB: "4096", cpuCount: "4")
        #expect(request.arguments == ["run", "--iso", "/tmp/Luna OS, preview.iso", "--memory", "4096", "--cpus", "4", "--name", "default"])
    }

    @Test("Installed disk boot omits the installer")
    func installedArguments() throws {
        let request = try LunaISOLaunchRequest(isoPath: nil, memoryMiB: "8192", cpuCount: "2")
        #expect(request.arguments == ["run", "--memory", "8192", "--cpus", "2", "--name", "default"])
    }

    @Test("Malformed resource settings cannot launch", arguments: ["", "0", "-1", "3.5", "abc", "999999999999999999999"])
    func malformedResources(value: String) {
        #expect(throws: LunaISOLaunchError.self) {
            try LunaISOLaunchRequest(isoPath: nil, memoryMiB: value, cpuCount: "4")
        }
        #expect(throws: LunaISOLaunchError.self) {
            try LunaISOLaunchRequest(isoPath: nil, memoryMiB: "4096", cpuCount: value)
        }
    }

    @Test("An ISO selection must be an absolute single-line path", arguments: ["", "luna.iso", "/tmp/a\n.iso", "/tmp/a\u{0}.iso"])
    func malformedPaths(value: String) {
        #expect(throws: LunaISOLaunchError.self) {
            try LunaISOLaunchRequest(isoPath: value, memoryMiB: "4096", cpuCount: "4")
        }
    }
}
