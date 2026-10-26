# IntelliKit

- Baseline: Swift tools 6.0, iOS 16 / macOS 13. Do not use newer syntax without compiler gates.
- Each capability has an independent product and target. IntelliKit is the umbrella.
- No UIKit, app models, authentication, default account, network client or third-party SDK in the first batch.
- Preserve attribution and document source provenance and behavior changes.
- Caller supplies limits, image policy and file ownership; throw real failures.
- Keep source files intact. File APIs only read local files and never delete originals.
- Test individual imports, umbrella APIs, image format/orientation/alpha/metadata/multiframe/size failures.
- Record actual runtime and compiler versions separately from declared compatibility.
