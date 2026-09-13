#!/usr/bin/env python3
"""Run the synchronous core test methods when Command Line Tools lack XCTest.

This is a small assertion adapter, not the XCTest runner. Keep swift test as the
primary test command on a full Xcode installation.
"""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
tests = (root / 'Tests/YiyiCoreTests/YiyiCoreTests.swift').read_text()
methods = re.findall(r'^    func (test\w+)\(\)( throws)?', tests, re.M)
shim = r'''
import Foundation
class XCTestCase {}
func fail(_ message: String, _ file: StaticString, _ line: UInt) -> Never {
    fatalError("\(file):\(line): \(message)")
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { fail("Expected true. " + message, file, line) } } catch { fail("\(error)", file, line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { fail("Expected false. " + message, file, line) } } catch { fail("\(error)", file, line) }
}
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try lhs() != rhs() { fail("Values differ. " + message, file, line) } } catch { fail("\(error)", file, line) }
}
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() != nil { fail("Expected nil. " + message, file, line) } } catch { fail("\(error)", file, line) }
}
func XCTAssertNotNil<T>(_ value: @autoclosure () throws -> T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() == nil { fail("Expected non-nil. " + message, file, line) } } catch { fail("\(error)", file, line) }
}
func XCTAssertNoThrow<T>(_ value: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value() } catch { fail("Unexpected error: \(error). " + message, file, line) }
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {
    do { _ = try value(); fail("Expected an error. " + message, file, line) } catch { handler(error) }
}
func XCTUnwrap<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value = try value() else { fail("Expected non-nil", file, line) }; return value
}
'''
tests = re.sub(r'^(?:@testable )?import (?:XCTest|YiyiCore)\n', '', tests, flags=re.M)
runner = '\n@main struct CoreChecks { static func main() throws {\nlet suite = YiyiCoreTests()\n'
for name, throwing in methods:
    runner += f'{"try " if throwing else ""}suite.{name}()\n'
runner += f'print("PASS: {len(methods)} core test methods (standalone assertion adapter)")\n}}}}\n'
with tempfile.TemporaryDirectory(prefix='yiyi-core-checks-') as directory:
    source = Path(directory) / 'CoreChecks.swift'
    binary = Path(directory) / 'core-checks'
    source.write_text(shim + tests + runner)
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', *map(str, sorted((root / 'Sources/YiyiCore').glob('*.swift'))), str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
