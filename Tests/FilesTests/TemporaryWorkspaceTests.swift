import Foundation
import IntelliKitFiles
import Testing

private func parent() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

@Test func writeAndCopyPreserveOriginalAndListOnlyPublishedFiles() throws {
  let root = try parent()
  defer { try? FileManager.default.removeItem(at: root) }
  let original = root.appendingPathComponent("original.txt")
  let data = Data("source".utf8)
  try data.write(to: original)
  let workspace = try TemporaryWorkspace(parentDirectory: root)
  let first = try workspace.write(Data("export".utf8), named: "export.txt")
  let copied = try workspace.copyFile(from: original, named: "copied.txt")
  #expect(try Data(contentsOf: first) == Data("export".utf8))
  #expect(try Data(contentsOf: copied) == data)
  #expect(try Data(contentsOf: original) == data)
  #expect(try workspace.files() == [first, copied])
  try workspace.cleanup()
  #expect(FileManager.default.fileExists(atPath: original.path))
  #expect(!FileManager.default.fileExists(atPath: workspace.directory.path))
}

@Test(arguments: ["", ".", "..", "../escape", "child/file", "child\\file", "null\0byte"])
func rejectsNonFlatFilenames(_ filename: String) throws {
  let root = try parent()
  defer { try? FileManager.default.removeItem(at: root) }
  let workspace = try TemporaryWorkspace(parentDirectory: root)
  #expect(throws: WorkspaceError.invalidFilename) { try workspace.write(Data(), named: filename) }
  #expect(try workspace.files().isEmpty)
}

@Test func duplicateNamesDoNotReplacePreviouslyPublishedFile() throws {
  let workspace = try TemporaryWorkspace()
  defer { try? workspace.cleanup() }
  let url = try workspace.write(Data("keep".utf8), named: "same.txt")
  #expect(throws: WorkspaceError.fileAlreadyExists) { try workspace.write(Data("replace".utf8), named: "same.txt") }
  #expect(try Data(contentsOf: url) == Data("keep".utf8))
  #expect(try workspace.files() == [url])
}

@Test func failedInstallationDoesNotLeavePendingOrPublishedFiles() throws {
  let workspace = try TemporaryWorkspace()
  defer { try? workspace.cleanup() }
  #expect(throws: (any Error).self) { try workspace.write(Data("new".utf8), named: String(repeating: "a", count: 300)) }
  #expect(try workspace.files().isEmpty)
  #expect(try FileManager.default.contentsOfDirectory(atPath: workspace.directory.path).isEmpty)
}

@Test func rejectsRemoteParentsDirectoriesAndSymbolicLinkSources() throws {
  let root = try parent()
  defer { try? FileManager.default.removeItem(at: root) }
  let workspace = try TemporaryWorkspace(parentDirectory: root)
  #expect(throws: WorkspaceError.fileURLRequired) {
    try TemporaryWorkspace(parentDirectory: URL(string: "https://example.invalid")!)
  }
  #expect(throws: WorkspaceError.regularFileRequired) { try workspace.copyFile(from: root, named: "directory") }
  let source = root.appendingPathComponent("source")
  try Data("keep".utf8).write(to: source)
  let link = root.appendingPathComponent("link")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
  #expect(throws: WorkspaceError.regularFileRequired) { try workspace.copyFile(from: link, named: "copy") }
  #expect(try workspace.files().isEmpty)
}

@Test func targetSymbolicLinkIsNotFollowedOrOverwritten() throws {
  let root = try parent()
  defer { try? FileManager.default.removeItem(at: root) }
  let source = root.appendingPathComponent("source")
  try Data("keep".utf8).write(to: source)
  let workspace = try TemporaryWorkspace(parentDirectory: root)
  let link = workspace.directory.appendingPathComponent("link")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
  #expect(throws: WorkspaceError.fileAlreadyExists) { try workspace.write(Data("bad".utf8), named: "link") }
  #expect(try Data(contentsOf: source) == Data("keep".utf8))
}

@Test func cleanupIsIdempotentAndClosedWorkspaceCannotBeReused() throws {
  let root = try parent()
  defer { try? FileManager.default.removeItem(at: root) }
  let workspace = try TemporaryWorkspace(parentDirectory: root)
  try workspace.cleanup()
  try workspace.cleanup()
  #expect(throws: WorkspaceError.closed) { try workspace.write(Data(), named: "new") }
  #expect(FileManager.default.fileExists(atPath: root.path))
}

@Test func missingWorkspaceCleanupDoesNotRemoveParent() throws {
  let root = try parent()
  defer { try? FileManager.default.removeItem(at: root) }
  let workspace = try TemporaryWorkspace(parentDirectory: root)
  try FileManager.default.removeItem(at: workspace.directory)
  try workspace.cleanup()
  #expect(FileManager.default.fileExists(atPath: root.path))
}

@Test func replacementDirectoryIsNotDeleted() throws {
  let root = try parent()
  defer { try? FileManager.default.removeItem(at: root) }
  let workspace = try TemporaryWorkspace(parentDirectory: root)
  let moved = root.appendingPathComponent("moved-original", isDirectory: true)
  try FileManager.default.moveItem(at: workspace.directory, to: moved)
  try FileManager.default.createDirectory(at: workspace.directory, withIntermediateDirectories: false)
  let outsider = workspace.directory.appendingPathComponent("keep")
  try Data("external".utf8).write(to: outsider)
  #expect(throws: WorkspaceError.ownershipLost) { try workspace.cleanup() }
  #expect(throws: WorkspaceError.ownershipLost) { try workspace.write(Data(), named: "new") }
  #expect(try Data(contentsOf: outsider) == Data("external".utf8))
}

@Test func replacedRootSymlinkDoesNotExposeOrDeleteOtherDirectory() throws {
  let root = try parent()
  defer { try? FileManager.default.removeItem(at: root) }
  let workspace = try TemporaryWorkspace(parentDirectory: root)
  let outsider = root.appendingPathComponent("outside", isDirectory: true)
  try FileManager.default.createDirectory(at: outsider, withIntermediateDirectories: false)
  let keep = outsider.appendingPathComponent("keep")
  try Data("external".utf8).write(to: keep)
  try FileManager.default.moveItem(at: workspace.directory, to: root.appendingPathComponent("moved"))
  try FileManager.default.createSymbolicLink(at: workspace.directory, withDestinationURL: outsider)
  #expect(throws: WorkspaceError.ownershipLost) { try workspace.cleanup() }
  #expect(throws: WorkspaceError.ownershipLost) { try workspace.files() }
  #expect(try Data(contentsOf: keep) == Data("external".utf8))
}

@Test func deinitCleansOwnedDirectory() throws {
  var workspace: TemporaryWorkspace? = try TemporaryWorkspace()
  let directory = try #require(workspace?.directory)
  _ = try workspace?.write(Data("temporary".utf8), named: "item")
  workspace = nil
  #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test func concurrentWritersPublishDistinctCompleteFiles() async throws {
  let workspace = try TemporaryWorkspace()
  defer { try? workspace.cleanup() }
  let urls = try await withThrowingTaskGroup(of: URL.self) { group in
    for index in 0..<30 {
      group.addTask { try workspace.write(Data(String(index).utf8), named: String(index)) }
    }
    var results: [URL] = []
    for try await url in group { results.append(url) }
    return results
  }
  #expect(urls.count == 30)
  #expect(try workspace.files().count == 30)
  for url in urls { #expect(try Data(contentsOf: url) == Data(url.lastPathComponent.utf8)) }
}

@Test func cancellationDoesNotPublishOrDeleteAnyFile() async throws {
  let workspace = try TemporaryWorkspace()
  defer { try? workspace.cleanup() }
  let task = Task.detached {
    withUnsafeCurrentTask { $0?.cancel() }
    return try workspace.write(Data("cancelled".utf8), named: "cancelled")
  }
  do { _ = try await task.value; Issue.record("Unexpected success") } catch is CancellationError {} catch {
    Issue.record("Unexpected error: \(error)")
  }
  #expect(try workspace.files().isEmpty)
  #expect(try FileManager.default.contentsOfDirectory(atPath: workspace.directory.path).isEmpty)
}
