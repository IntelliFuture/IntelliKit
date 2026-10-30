import Foundation
import IntelliKitDiskCache
import XCTest

@MainActor final class DiskCacheTests: XCTestCase {
  private func root() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("IntelliKit-cache-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  private func cache(_ root: URL, _ name: String = "test", capacity: Int = 8192) throws -> DiskCache {
    try DiskCache(parentDirectory: root, namespace: name, capacityBytes: capacity)
  }
  private func entries(_ cache: DiskCache) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: cache.directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "entry" }
  }
  private func expectError(_ expected: DiskCacheError, _ action: () async throws -> Void,
                           file: StaticString = #filePath, line: UInt = #line) async {
    do { try await action(); XCTFail("Expected \(expected)", file: file, line: line) }
    catch let error as DiskCacheError { XCTAssertEqual(error, expected, file: file, line: line) }
    catch { XCTFail("Unexpected \(error)", file: file, line: line) }
  }

  func testPersistsAcrossReopenAndDoesNotPersistRawKeyInFilename() async throws {
    let root = try root(); let store = try cache(root)
    let key = "../../user:123|lang=ja?secret=" + String(repeating: "長", count: 1000)
    try await store.write(Data("hello".utf8), forKey: key, schemaVersion: 3, ttl: nil)
    let files = try entries(store)
    XCTAssertEqual(files.count, 1); XCTAssertEqual(files[0].lastPathComponent.count, 70)
    await store.close()
    let reopened = try cache(root)
    let value = try await reopened.read(forKey: key, schemaVersion: 3)
    XCTAssertEqual(value?.data, Data("hello".utf8)); XCTAssertNil(value?.expiresAt)
    let wrongSchema = try await reopened.read(forKey: key, schemaVersion: 4)
    XCTAssertNil(wrongSchema)
    await reopened.close()
  }

  func testTTLStaleReadAndPruneAtExactBoundary() async throws {
    let root = try root()
    let first = try DiskCache(parentDirectory: root, namespace: "ttl", capacityBytes: 8192,
      clock: { Date(timeIntervalSince1970: 100) })
    try await first.write(Data([1]), forKey: "key", ttl: 10)
    await first.close()
    let second = try DiskCache(parentDirectory: root, namespace: "ttl", capacityBytes: 8192,
      clock: { Date(timeIntervalSince1970: 110) })
    let fresh = try await second.read(forKey: "key")
    let stale = try await second.read(forKey: "key", allowExpired: true)
    XCTAssertNil(fresh); XCTAssertEqual(stale?.data, Data([1]))
    XCTAssertTrue(stale?.isExpired(at: Date(timeIntervalSince1970: 110)) == true)
    try await second.prune()
    XCTAssertTrue(try entries(second).isEmpty)
    await second.close()
  }

  func testCapacityEvictsOldestWrittenAndOversizeKeepsPreviousValue() async throws {
    let root = try root(); let store = try cache(root, capacity: 1100)
    let data = Data(repeating: 1, count: 200)
    try await store.write(data, forKey: "old", ttl: nil)
    let old = try XCTUnwrap(entries(store).first)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: old.path)
    try await store.write(data, forKey: "middle", ttl: nil)
    try await store.write(data, forKey: "new", ttl: nil)
    let missing = try await store.read(forKey: "old")
    XCTAssertNil(missing)
    let size = try await store.diskSize(); XCTAssertLessThanOrEqual(size, 1100)
    await expectError(.entryTooLarge) { try await store.write(Data(count: 1101), forKey: "new", ttl: nil) }
    let retained = try await store.read(forKey: "new"); XCTAssertEqual(retained?.data, data)
    await store.close()
  }

  func testNamespacesAndClearPreserveParentAndUnrelatedFiles() async throws {
    let root = try root(); let a = try cache(root, "a/../a"); let b = try cache(root, "b")
    let original = root.appendingPathComponent("original.txt"); try Data([7]).write(to: original)
    let unrelated = a.directory.appendingPathComponent("unrelated.txt"); try Data([8]).write(to: unrelated)
    try await a.write(Data([1]), forKey: "same", ttl: nil)
    try await b.write(Data([2]), forKey: "same", ttl: nil)
    try await a.removeAll()
    let value = try await b.read(forKey: "same"); XCTAssertEqual(value?.data, Data([2]))
    XCTAssertEqual(try Data(contentsOf: original), Data([7])); XCTAssertEqual(try Data(contentsOf: unrelated), Data([8]))
    await a.close(); await b.close()
  }

  func testExclusiveOwnerAndClosedOperations() async throws {
    let root = try root(); let first = try cache(root)
    XCTAssertThrowsError(try cache(root)) { XCTAssertEqual($0 as? DiskCacheError, .alreadyOpen) }
    await first.close(); await first.close()
    await expectError(.closed) { _ = try await first.read(forKey: "x") }
    let next = try cache(root); await next.close()
  }

  func testCorruptEntryThrowsWithoutBeingSilentlyDeleted() async throws {
    let store = try cache(root())
    try await store.write(Data([1]), forKey: "x", ttl: nil)
    let path = try XCTUnwrap(entries(store).first)
    try Data("broken".utf8).write(to: path)
    await expectError(.corruptEntry) { _ = try await store.read(forKey: "x") }
    XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    try await store.remove(forKey: "x"); try await store.remove(forKey: "x")
    await store.close()
  }

  func testEntrySymlinkAndReplacedRootCannotDeleteExternalData() async throws {
    let root = try root(); let store = try cache(root)
    let source = root.appendingPathComponent("original"); try Data([9]).write(to: source)
    try await store.write(Data([1]), forKey: "x", ttl: nil)
    let path = try XCTUnwrap(entries(store).first)
    try FileManager.default.removeItem(at: path)
    try FileManager.default.createSymbolicLink(at: path, withDestinationURL: source)
    await expectError(.unsafeEntry) { _ = try await store.read(forKey: "x") }
    await expectError(.unsafeEntry) { try await store.removeAll() }
    XCTAssertEqual(try Data(contentsOf: source), Data([9]))
    let moved = root.appendingPathComponent("moved")
    try FileManager.default.moveItem(at: store.directory, to: moved)
    try FileManager.default.createSymbolicLink(at: store.directory, withDestinationURL: root)
    await expectError(.ownershipLost) { try await store.removeAll() }
    XCTAssertEqual(try Data(contentsOf: source), Data([9]))
    await store.close()
  }

  func testInvalidConfigurationAndLifetimeDoNotOverwrite() async throws {
    let root = try root(); let store = try cache(root)
    XCTAssertThrowsError(try cache(root, capacity: 0))
    XCTAssertThrowsError(try cache(URL(string: "https://example.invalid")!))
    XCTAssertThrowsError(try cache(root, ""))
    try await store.write(Data([1]), forKey: "x", ttl: nil)
    for ttl in [-1.0, .infinity, .nan] {
      await expectError(.invalidLifetime) { try await store.write(Data([2]), forKey: "x", ttl: ttl) }
    }
    let value = try await store.read(forKey: "x"); XCTAssertEqual(value?.data, Data([1]))
    await store.close()
  }

  func testParallelWritesAndPreCancelledWrite() async throws {
    let store = try cache(root(), capacity: 100_000)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<50 { group.addTask { try await store.write(Data([UInt8(index)]), forKey: "\(index)", ttl: nil) } }
      try await group.waitForAll()
    }
    XCTAssertEqual(try entries(store).count, 50)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await store.write(Data([99]), forKey: "cancelled", ttl: nil)
    }
    do { try await task.value; XCTFail("Unexpected success") } catch is CancellationError {}
    let value = try await store.read(forKey: "cancelled"); XCTAssertNil(value)
    await store.close()
  }

  func testSmallerCapacityPruneAndMarkerLoss() async throws {
    let root = try root(); let first = try cache(root)
    try await first.write(Data(count: 1000), forKey: "x", ttl: nil)
    await first.close()
    let small = try cache(root, capacity: 512)
    await expectError(.entryTooLarge) { _ = try await small.read(forKey: "x") }
    try await small.prune()
    let size = try await small.diskSize(); XCTAssertEqual(size, 0)
    try FileManager.default.removeItem(at: small.directory.appendingPathComponent(".owner"))
    await expectError(.ownershipLost) { try await small.removeAll() }
    await small.close()
  }
  func testEnvelopeOverheadAlsoCountsAndAtomicReplacementKeepsOneEntry() async throws {
    let store = try cache(root(), capacity: 600)
    try await store.write(Data([1]), forKey: "x", ttl: nil)
    await expectError(.entryTooLarge) { try await store.write(Data(count: 500), forKey: "x", ttl: nil) }
    let before = try await store.read(forKey: "x"); XCTAssertEqual(before?.data, Data([1]))
    try await store.write(Data([2, 3]), forKey: "x", ttl: nil)
    let after = try await store.read(forKey: "x"); XCTAssertEqual(after?.data, Data([2, 3]))
    XCTAssertEqual(try entries(store).count, 1)
    await store.close()
  }

  func testCopiedEnvelopeUnderDifferentKeyIsCorruption() async throws {
    let store = try cache(root())
    try await store.write(Data([1]), forKey: "a", ttl: nil)
    let a = try XCTUnwrap(entries(store).first)
    let bytes = try Data(contentsOf: a)
    try await store.write(Data([2]), forKey: "b", ttl: nil)
    let b = try XCTUnwrap(entries(store).first { $0 != a })
    try bytes.write(to: b)
    await expectError(.corruptEntry) { _ = try await store.read(forKey: "b") }
    await store.close()
  }

  func testReplacedDirectoryAndLeaseAreRejected() async throws {
    let root = try root(); let store = try cache(root)
    let lock = store.directory.appendingPathComponent(".lock")
    try FileManager.default.moveItem(at: lock, to: store.directory.appendingPathComponent(".old-lock"))
    try Data().write(to: lock)
    await expectError(.ownershipLost) { try await store.write(Data([1]), forKey: "x", ttl: nil) }
    await store.close()
    // Recreate the namespace inode while an owner still holds the old one.
    let fresh = try cache(root, "fresh")
    try FileManager.default.moveItem(at: fresh.directory, to: root.appendingPathComponent("moved"))
    try FileManager.default.createDirectory(at: fresh.directory, withIntermediateDirectories: false)
    let sentinel = fresh.directory.appendingPathComponent("external"); try Data([4]).write(to: sentinel)
    await expectError(.ownershipLost) { try await fresh.removeAll() }
    XCTAssertEqual(try Data(contentsOf: sentinel), Data([4]))
    await fresh.close()
  }

  func testMissingDirectoryReportsIOFailureAndUnownedDirectoryIsNotAdopted() async throws {
    let root = try root(); let store = try cache(root)
    let directory = store.directory
    await store.close()
    try FileManager.default.removeItem(at: directory.appendingPathComponent(".owner"))
    let sentinel = directory.appendingPathComponent("external"); try Data([5]).write(to: sentinel)
    XCTAssertThrowsError(try cache(root)) { XCTAssertEqual($0 as? DiskCacheError, .directoryNotOwned) }
    XCTAssertEqual(try Data(contentsOf: sentinel), Data([5]))
    let fresh = try cache(root, "fresh")
    try FileManager.default.removeItem(at: fresh.directory)
    do { _ = try await fresh.read(forKey: "x"); XCTFail("Missing directory must be reported") }
    catch { XCTAssertTrue(error is CocoaError) }
    await fresh.close()
  }

}
