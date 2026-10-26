# IntelliKit

- Baseline: Swift tools 6.0, iOS 16 / macOS 13. Do not use newer syntax without compiler gates.
- Each capability has an independent product and target. IntelliKit is the umbrella.
- No UIKit, app models, authentication, default account or third-party SDK. Networking is a separate bounded transport product; DiskCache never fetches remotely.
- Preserve attribution and document source provenance and behavior changes.
- Caller supplies limits, image policy and file ownership; throw real failures.
- DiskCache may atomically replace and evict only its owned namespace entries; never clear its parent or adopt a nonempty unmarked directory. Keep failures observable.
- Locked uses availability-gated Mutex with an independently tested NSLock fallback; do not raise the deployment baseline.
- Keep source files intact. Image APIs are read-only; Files may write and clean only their own newly-created workspace, never arbitrary source paths or the parent directory.
- Concurrency registration/callback/cancel handlers must run outside locks. Cover cancellation before and during registration, and repeated callbacks.
- Test individual imports, umbrella APIs, image format/orientation/alpha/metadata/multiframe/size failures.
- Record actual runtime and compiler versions separately from declared compatibility.
