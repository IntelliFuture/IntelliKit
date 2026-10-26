import Foundation
import IntelliKit
import Testing

@Test func umbrellaExposesNetworkingAndCacheWithoutIndividualImports() async throws {
  let policy = try HTTPDownloadPolicy(maximumBytes: 256)
  #expect(policy.maximumBytes == 256)
  let downloader: BoundedHTTPDownload.Type = BoundedHTTPDownload.self
  _ = downloader
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = try DiskCache(parentDirectory: root, namespace: "umbrella", capacityBytes: 4096)
  try await store.write(Data([1]), forKey: "key", ttl: nil)
  let entry: DiskCacheEntry? = try await store.read(forKey: "key")
  #expect(entry?.data == Data([1]))
  await store.close()
}
