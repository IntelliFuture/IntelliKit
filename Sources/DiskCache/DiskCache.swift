import CryptoKit
import Darwin
import Foundation

public enum DiskCacheError: Error, Equatable {
  case invalidConfiguration, invalidLifetime, entryTooLarge, corruptEntry
  case ownershipLost, unsafeEntry, directoryNotOwned, alreadyOpen, closed
}

public struct DiskCacheEntry: Sendable {
  public let data: Data
  public let schemaVersion: Int
  public let savedAt: Date
  public let expiresAt: Date?
  public func isExpired(at date: Date = Date()) -> Bool { expiresAt.map { date >= $0 } ?? false }
}

/// Persistent, bounded Data cache. One live owner per namespace, enforced by an advisory file lock.
/// Calls serialize within the actor without suspension. No account, networking, or UI dependencies.
public actor DiskCache {
  public nonisolated let directory: URL
  private let capacityBytes: Int
  private let clock: @Sendable () -> Date
  private let manager = FileManager()
  private let identity: DirectoryIdentity
  private let lease: DirectoryLease
  private let marker: Data
  private var isClosed = false

  private struct Envelope: Codable {
    let format: Int
    let keyDigest: String
    let schemaVersion: Int
    let savedAt: Date
    let expiresAt: Date?
    let data: Data
  }
  private struct FileInfo {
    let url: URL
    let size: Int
    let modified: Date
  }

  /// The parent is never cleared. Namespace must explicitly encode account/version boundaries as needed.
  /// Capacity measures encoded entry bytes; filesystem overhead, marker/lock and temporary writes are extra.
  public init(parentDirectory: URL, namespace: String, capacityBytes: Int,
              clock: @escaping @Sendable () -> Date = { Date() }) throws {
    guard parentDirectory.isFileURL, !namespace.isEmpty, capacityBytes > 0 else {
      throw DiskCacheError.invalidConfiguration
    }
    self.capacityBytes = capacityBytes
    self.clock = clock
    let parent = parentDirectory.standardizedFileURL.resolvingSymlinksInPath()
    try manager.createDirectory(at: parent, withIntermediateDirectories: true)
    let digest = Self.digest(namespace)
    directory = parent.appendingPathComponent("intellikit-cache-v1-" + digest, isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    identity = try DirectoryIdentity(directory)
    lease = try DirectoryLease(directory.appendingPathComponent(".lock"))
    marker = Data(("IntelliKitDiskCache:1:" + digest).utf8)
    let markerURL = directory.appendingPathComponent(".owner")
    if let attributes = try Self.attributesIfPresent(markerURL) {
      guard attributes[.type] as? FileAttributeType == .typeRegular,
        (attributes[.size] as? NSNumber)?.intValue == marker.count,
        try Data(contentsOf: markerURL) == marker else { throw DiskCacheError.directoryNotOwned }
    } else {
      guard try manager.contentsOfDirectory(atPath: directory.path).allSatisfy({ $0 == ".lock" }) else {
        throw DiskCacheError.directoryNotOwned
      }
      try marker.write(to: markerURL, options: .withoutOverwriting)
    }
  }

  /// Missing, expired and mismatched-schema entries are misses; corruption and I/O failures throw.
  /// An expired entry is retained so a caller can explicitly request stale data for its own SWR policy.
  public func read(forKey key: String, schemaVersion: Int = 1,
                   allowExpired: Bool = false) throws -> DiskCacheEntry? {
    try checkAccess()
    let url = entryURL(key)
    guard let info = try fileInfo(url) else { return nil }
    guard info.size <= capacityBytes else { throw DiskCacheError.entryTooLarge }
    let envelope = try decode(url, expectedDigest: Self.digest(key))
    guard envelope.schemaVersion == schemaVersion else { return nil }
    let entry = DiskCacheEntry(data: envelope.data, schemaVersion: envelope.schemaVersion,
      savedAt: envelope.savedAt, expiresAt: envelope.expiresAt)
    try Task.checkCancellation()
    return !allowExpired && entry.isExpired(at: clock()) ? nil : entry
  }

  /// Atomically replaces one entry, then evicts oldest-written entries to capacity (not LRU).
  /// A post-publication eviction failure throws but does not roll back the already committed entry.
  public func write(_ data: Data, forKey key: String, schemaVersion: Int = 1,
                    ttl: TimeInterval?) throws {
    try checkAccess()
    guard data.count <= capacityBytes else { throw DiskCacheError.entryTooLarge }
    if let ttl, !ttl.isFinite || ttl < 0 { throw DiskCacheError.invalidLifetime }
    let now = clock()
    let expiry = ttl.map { now.addingTimeInterval($0) }
    guard now.timeIntervalSince1970.isFinite,
      expiry?.timeIntervalSince1970.isFinite != false else { throw DiskCacheError.invalidLifetime }
    let envelope = Envelope(format: 1, keyDigest: Self.digest(key), schemaVersion: schemaVersion,
      savedAt: now, expiresAt: expiry, data: data)
    let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
    let encoded = try encoder.encode(envelope)
    guard encoded.count <= capacityBytes else { throw DiskCacheError.entryTooLarge }
    let url = entryURL(key)
    _ = try fileInfo(url) // Refuse links/directories instead of replacing somebody else's item.
    try Task.checkCancellation()
    try encoded.write(to: url, options: .atomic)
    try evictToCapacity(protecting: url)
  }

  public func remove(forKey key: String) throws {
    try checkAccess()
    let url = entryURL(key)
    if try fileInfo(url) != nil { try manager.removeItem(at: url) }
  }

  /// Removes only owned entry files. Leaves the namespace, marker, lock and unrelated files intact.
  public func removeAll() throws {
    try checkAccess()
    for file in try entries() {
      try Task.checkCancellation()
      try manager.removeItem(at: file.url)
    }
  }

  public func diskSize() throws -> Int {
    try checkAccess()
    return try totalSize(entries())
  }

  /// Removes expired entries and enforces the current capacity, useful after reopening at a smaller limit.
  /// Corrupt entries throw and remain available for explicit remove/removeAll, rather than hiding failure.
  public func prune() throws {
    try checkAccess()
    let now = clock()
    for file in try entries() {
      try Task.checkCancellation()
      // Oversized entries cannot be read safely under this cache's current limit.
      if file.size > capacityBytes {
        try manager.removeItem(at: file.url)
        continue
      }
      let envelope = try decode(file.url, expectedDigest: file.url.deletingPathExtension().lastPathComponent)
      if let expiry = envelope.expiresAt, now >= expiry { try manager.removeItem(at: file.url) }
    }
    try evictToCapacity(protecting: nil)
  }

  /// Releases the namespace for another owner without deleting persistent entries. Idempotent.
  public func close() {
    guard !isClosed else { return }
    isClosed = true
    lease.close()
  }

  private func checkAccess() throws {
    guard !isClosed else { throw DiskCacheError.closed }
    try Task.checkCancellation()
    guard try DirectoryIdentity(directory) == identity else { throw DiskCacheError.ownershipLost }
    try lease.validate()
    let markerURL = directory.appendingPathComponent(".owner")
    guard let attributes = try Self.attributesIfPresent(markerURL),
      attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.size] as? NSNumber)?.intValue == marker.count,
      try Data(contentsOf: markerURL) == marker else { throw DiskCacheError.ownershipLost }
  }

  private func decode(_ url: URL, expectedDigest: String) throws -> Envelope {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var bytes = Data()
    while bytes.count < capacityBytes {
      try Task.checkCancellation()
      let chunk = try handle.read(upToCount: min(64 * 1024, capacityBytes - bytes.count)) ?? Data()
      if chunk.isEmpty { break }
      bytes.append(chunk)
    }
    // Bound allocation even if another process grows the file after the initial stat.
    guard (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw DiskCacheError.entryTooLarge }
    let envelope: Envelope
    do { envelope = try PropertyListDecoder().decode(Envelope.self, from: bytes) }
    catch { throw DiskCacheError.corruptEntry }
    guard envelope.format == 1, envelope.keyDigest == expectedDigest,
      envelope.savedAt.timeIntervalSince1970.isFinite,
      envelope.expiresAt?.timeIntervalSince1970.isFinite != false else { throw DiskCacheError.corruptEntry }
    return envelope
  }

  private func entryURL(_ key: String) -> URL { directory.appendingPathComponent(Self.digest(key) + ".entry") }
  private static func digest(_ string: String) -> String {
    SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func fileInfo(_ url: URL) throws -> FileInfo? {
    guard let attributes = try Self.attributesIfPresent(url) else { return nil }
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.referenceCount] as? NSNumber)?.intValue == 1,
      let size = (attributes[.size] as? NSNumber)?.intValue, size >= 0 else { throw DiskCacheError.unsafeEntry }
    return FileInfo(url: url, size: size, modified: attributes[.modificationDate] as? Date ?? .distantPast)
  }

  private func entries() throws -> [FileInfo] {
    try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).compactMap { url in
      let name = url.deletingPathExtension().lastPathComponent
      guard url.pathExtension == "entry", name.utf8.count == 64,
        name.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
      return try fileInfo(url)
    }
  }

  private func totalSize(_ files: [FileInfo]) throws -> Int {
    try files.reduce(0) { total, file in
      let (sum, overflow) = total.addingReportingOverflow(file.size)
      guard !overflow else { throw DiskCacheError.entryTooLarge }
      return sum
    }
  }

  private func evictToCapacity(protecting protected: URL?) throws {
    let files = try entries()
    var size = try totalSize(files)
    let ordered = files.filter { $0.url != protected }.sorted {
      $0.modified == $1.modified ? $0.url.path < $1.url.path : $0.modified < $1.modified
    }
    for file in ordered where size > capacityBytes {
      try manager.removeItem(at: file.url)
      size -= file.size
    }
  }

  private static func attributesIfPresent(_ url: URL) throws -> [FileAttributeKey: Any]? {
    do { return try FileManager.default.attributesOfItem(atPath: url.path) }
    catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return nil }
  }
}

private struct DirectoryIdentity: Equatable {
  let device: UInt64
  let inode: UInt64
  init(_ url: URL) throws {
    guard url.standardizedFileURL.resolvingSymlinksInPath().path == url.path else { throw DiskCacheError.ownershipLost }
    let values = try FileManager.default.attributesOfItem(atPath: url.path)
    guard values[.type] as? FileAttributeType == .typeDirectory,
      let device = values[.systemNumber] as? NSNumber, let inode = values[.systemFileNumber] as? NSNumber else {
      throw DiskCacheError.ownershipLost
    }
    self.device = device.uint64Value; self.inode = inode.uint64Value
  }
}

/// Private descriptor lifetime. Only the owning actor accesses it after initialization.
private final class DirectoryLease: @unchecked Sendable {
  private var descriptor: Int32
  private let url: URL
  init(_ url: URL) throws {
    self.url = url
    descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    var info = stat()
    guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else {
      Darwin.close(descriptor); descriptor = -1; throw DiskCacheError.unsafeEntry
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let code = errno
      Darwin.close(descriptor); descriptor = -1
      if code == EWOULDBLOCK { throw DiskCacheError.alreadyOpen }
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
  }
  func validate() throws {
    var actual = stat(); var held = stat()
    guard lstat(url.path, &actual) == 0, fstat(descriptor, &held) == 0,
      actual.st_dev == held.st_dev, actual.st_ino == held.st_ino else { throw DiskCacheError.ownershipLost }
  }
  func close() {
    guard descriptor >= 0 else { return }
    Darwin.close(descriptor); descriptor = -1
  }
  deinit { close() }
}
