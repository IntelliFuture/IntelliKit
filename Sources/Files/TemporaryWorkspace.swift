import Foundation

public enum WorkspaceError: Error, Equatable {
  case fileURLRequired
  case invalidFilename
  case fileAlreadyExists
  case regularFileRequired
  case closed
  case ownershipLost
}

/// Owns one newly-created UUID directory. Keep this instance alive until consumers finish using its URLs.
/// Calls are serialized. Explicit cleanup throws real errors; deinit only attempts best-effort cleanup.
/// This is not a sandbox against hostile processes modifying the parent directory concurrently.
public final class TemporaryWorkspace: @unchecked Sendable {
  public let directory: URL
  private let identity: Identity
  private let fileManager = FileManager()
  private let lock = NSLock()
  private var closed = false
  private var filenames: [String] = []

  private struct Identity: Equatable {
    let device: UInt64
    let inode: UInt64
  }

  public init(parentDirectory: URL = FileManager.default.temporaryDirectory) throws {
    guard parentDirectory.isFileURL else { throw WorkspaceError.fileURLRequired }
    let parent = parentDirectory.standardizedFileURL.resolvingSymlinksInPath()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    directory = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
    do { identity = try Self.identity(at: directory, fileManager: fileManager) }
    catch { try? fileManager.removeItem(at: directory); throw error }
  }

  /// Installs a complete file without replacing any existing target. No partial target is published.
  @discardableResult
  public func write(_ data: Data, named filename: String) throws -> URL {
    try install(named: filename) { stage in try data.write(to: stage, options: .withoutOverwriting) }
  }

  /// Copies a regular file into the workspace; the source is never moved, overwritten or deleted.
  @discardableResult
  public func copyFile(from source: URL, named filename: String) throws -> URL {
    guard source.isFileURL else { throw WorkspaceError.fileURLRequired }
    return try install(named: filename) { stage in
      let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true else { throw WorkspaceError.regularFileRequired }
      try fileManager.copyItem(at: source, to: stage)
    }
  }

  public func files() throws -> [URL] {
    lock.lock(); defer { lock.unlock() }
    try validateRoot()
    return filenames.map { directory.appendingPathComponent($0) }
  }

  /// Idempotent after success, or if the owned directory is already gone. Never clears the parent.
  public func cleanup() throws {
    lock.lock(); defer { lock.unlock() }
    if closed { return }
    do {
      try validateRoot()
      try fileManager.removeItem(at: directory)
    } catch {
      guard Self.isMissing(error) else { throw error }
    }
    closed = true
    filenames = []
  }

  deinit { try? cleanup() }

  private func install(named filename: String, prepare: (URL) throws -> Void) throws -> URL {
    guard !filename.isEmpty, filename != ".", filename != "..",
      !filename.contains("/"), !filename.contains("\\"), !filename.contains("\0") else {
      throw WorkspaceError.invalidFilename
    }
    lock.lock(); defer { lock.unlock() }
    try validateRoot()
    try Task.checkCancellation()
    let target = directory.appendingPathComponent(filename)
    guard !itemExists(target) else { throw WorkspaceError.fileAlreadyExists }
    let stage = directory.appendingPathComponent(".pending-" + UUID().uuidString)
    do {
      try prepare(stage)
      try Task.checkCancellation()
      try validateRoot()
      guard !itemExists(target) else { throw WorkspaceError.fileAlreadyExists }
      try fileManager.moveItem(at: stage, to: target)
      filenames.append(filename)
      return target
    } catch {
      // If an external actor replaced the root, do not follow the replacement to remove a pending path.
      if (try? validateRoot()) != nil { try? fileManager.removeItem(at: stage) }
      throw error
    }
  }

  private func itemExists(_ url: URL) -> Bool {
    (try? fileManager.attributesOfItem(atPath: url.path)) != nil
  }

  private func validateRoot() throws {
    guard !closed else { throw WorkspaceError.closed }
    guard directory.resolvingSymlinksInPath().standardizedFileURL.path == directory.path,
      try Self.identity(at: directory, fileManager: fileManager) == identity else { throw WorkspaceError.ownershipLost }
  }

  private static func identity(at url: URL, fileManager: FileManager) throws -> Identity {
    let values = try fileManager.attributesOfItem(atPath: url.path)
    guard values[.type] as? FileAttributeType == .typeDirectory,
      let device = values[.systemNumber] as? NSNumber,
      let inode = values[.systemFileNumber] as? NSNumber else { throw WorkspaceError.ownershipLost }
    return Identity(device: device.uint64Value, inode: inode.uint64Value)
  }

  private static func isMissing(_ error: Error) -> Bool {
    guard let error = error as? CocoaError else { return false }
    return error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
  }
}
