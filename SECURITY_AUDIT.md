# Security Audit Report - Keystone

**Date:** 2026-04-06
**Scope:** Full codebase review (234 Swift source files, CI/CD workflows, package dependencies)
**Project:** Keystone - A cross-platform SwiftUI code editor component (fork of Runestone)

---

## Executive Summary

Keystone is a client-side text editor library with no network I/O, authentication, or persistent storage of user data. Its attack surface is primarily through **malicious document content** and **crafted text input** that flows through the TreeSitter C interop layer, regex engine, and unsafe pointer operations. The audit identified **4 critical**, **6 high**, and several medium-severity findings.

---

## CRITICAL Findings

### C1. Memory Leak on Failure Path in Unsafe Buffer Allocation
**File:** `Sources/Keystone/Library/NSString+Helpers.swift:13-28`
**Type:** Memory Leak / Denial of Service

```swift
func getBytes(in range: NSRange, encoding: String.Encoding, usedLength: inout Int) -> UnsafePointer<Int8>? {
    let byteRange = ByteRange(utf16Range: range)
    let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: byteRange.length.value)
    let didGetBytes = getBytes(buffer, maxLength: byteRange.length.value, ...)
    if didGetBytes {
        return UnsafePointer<Int8>(buffer)
    } else {
        return nil  // BUG: buffer is never deallocated
    }
}
```

When `getBytes` fails, the allocated buffer is leaked. Additionally, `byteRange.length.value` is not validated before allocation - a very large document could trigger excessive memory consumption. The returned pointer has no ownership semantics, making use-after-free possible if callers mismanage its lifetime.

**Impact:** Memory exhaustion DoS; use-after-free in callers.

---

### C2. Forced Null Pointer Dereference in TreeSitter C Interop
**File:** `Sources/Keystone/TreeSitter/TreeSitterQuery.swift:59, 101`
**Type:** Null Pointer Crash / Denial of Service

```swift
func captureName(forId id: UInt32) -> String {
    let cString = ts_query_capture_name_for_id(pointer, id, lengthPointer)
    return String(cString: cString!)  // Force-unwrap of C API return
}

private func stringValue(forId id: uint) -> String {
    let cString = ts_query_string_value_for_id(pointer, id, lengthPointer)
    return String(cString: cString!)  // Force-unwrap of C API return
}
```

Both TreeSitter C functions can return `NULL` for invalid IDs. Force-unwrapping crashes the app immediately. A malformed or corrupted language grammar file triggers this.

**Impact:** Guaranteed application crash.

---

### C3. Logic Bug - Wrong Capture Index in Predicate Evaluation
**File:** `Sources/Keystone/TextView/SyntaxHighlighting/Internal/TreeSitter/TreeSitterTextPredicatesEvaluator.swift:64`
**Type:** Logic Error / Incorrect Security-Relevant Behavior

```swift
func evaluate(using parameters: TreeSitterTextPredicate.CaptureEqualsCaptureParameters) -> Bool {
    guard let lhsCapture = match.capture(forIndex: parameters.lhsCaptureIndex) else {
        return false
    }
    guard let rhsCapture = match.capture(forIndex: parameters.lhsCaptureIndex) else {
        //                                                  ^^^ BUG: should be rhsCaptureIndex
        return false
    }
```

The right-hand side capture lookup uses `lhsCaptureIndex` instead of `rhsCaptureIndex`. This means `#eq?` capture-vs-capture predicates in TreeSitter queries always compare a capture against itself, causing incorrect syntax highlighting and predicate evaluation.

**Impact:** Syntax highlighting predicates that compare two captures are silently broken. May cause incorrect code rendering.

---

### C4. Unbounded Pointer Arithmetic in Predicate Parsing
**File:** `Sources/Keystone/TreeSitter/TreeSitterQuery.swift:72-86`
**Type:** Heap Buffer Over-Read

```swift
while l < lengthPointer.pointee {
    let name = stringValue(forId: rawSteps.pointee.value_id)
    l += 1
    for i in 1 ..< .max {  // Unbounded loop
        let step = (rawSteps + UnsafePointer<TSQueryPredicateStep>.Stride(i)).pointee
        l += 1
        if step.type == TSQueryPredicateStepTypeDone { break }
    }
}
```

The inner loop iterates up to `Int.max` performing pointer arithmetic on `rawSteps` without any bounds checking against the allocated buffer size. If no `TSQueryPredicateStepTypeDone` sentinel is found (e.g., corrupted data), this reads arbitrary heap memory.

**Impact:** Out-of-bounds heap read; potential information disclosure; crash.

---

## HIGH Findings

### H1. Regex Denial of Service (ReDoS) via User-Controlled Patterns
**Files:**
- `Sources/Keystone/TextView/SearchAndReplace/SearchQuery.swift:74`
- `Sources/Keystone/Features/FindReplaceManager.swift:226`

User-supplied regex patterns are passed directly to `NSRegularExpression` with no complexity validation, timeout, or ReDoS protection. A pattern like `(a+)+b` matched against `"aaaaaaaaaaaaaac"` causes exponential backtracking that freezes the UI thread.

**Impact:** Application freeze / UI-thread DoS.

---

### H2. Integer Overflow in Range Arithmetic
**Files:**
- `Sources/Keystone/Library/TextEditHelper.swift:27,35,52,55`
- `Sources/Keystone/LineManager/LineManager.swift:65-68`
- `Sources/Keystone/Library/NSString+Helpers.swift:40`

Multiple locations perform unchecked `NSRange.location + NSRange.length` additions. Example:

```swift
let oldEndLinePosition = lineManager.linePosition(at: range.location + range.length)!
```

When `location + length > Int.max`, this wraps to a negative value, leading to invalid line position lookups and potential out-of-bounds access.

**Impact:** Out-of-bounds memory access; incorrect text operations.

---

### H3. Null Pointer in UnsafeBufferPointer Construction
**File:** `Sources/Keystone/TreeSitter/TreeSitterTree.swift:25-26`

```swift
let ptr = ts_tree_get_changed_ranges(pointer, otherTree.pointer, &count)
return UnsafeBufferPointer(start: ptr, count: Int(count)).map { ... }
```

`ts_tree_get_changed_ranges` can return `NULL`. Creating an `UnsafeBufferPointer` with a null `start` and non-zero `count` is undefined behavior per Swift's documentation.

**Impact:** Undefined behavior; crash.

---

### H4. Unsafe Pointer Lifecycle - No Ownership Contract
**File:** `Sources/Keystone/TextView/Core/StringView.swift:71-82`

`StringViewBytesResult` holds an `UnsafePointer<Int8>` with an explicit comment: "The bytes are not deallocated by this type." There is no clear ownership contract, no `deinit` cleanup, and callers must manually manage deallocation. This is a class-wide pattern that enables use-after-free and double-free bugs.

**Impact:** Use-after-free; double-free; memory corruption.

---

### H5. Integer Truncation in Byte-to-UTF16 Conversion
**File:** `Sources/Keystone/TextView/SyntaxHighlighting/Internal/TreeSitter/TreeSitterTextPredicatesEvaluator.swift:82`

```swift
let range = NSRange(location: byteRange.location.value / 2, length: byteRange.length.value / 2)
```

Simple division by 2 truncates odd byte values, creating off-by-one range errors. No validation that the resulting NSRange is within string bounds before use in `stringView.substring(in:)`.

**Impact:** Off-by-one buffer read; potential out-of-bounds substring access.

---

### H6. UInt32 Overflow in TreeSitter Query Range
**File:** `Sources/Keystone/TreeSitter/TreeSitterQueryCursor.swift:21`

```swift
let end = UInt32((range.location + range.length).value)
```

If `range.location.value + range.length.value` exceeds `UInt32.max` (4GB), the `UInt32()` initializer traps in debug and truncates in release, passing incorrect byte ranges to the C API.

**Impact:** Incorrect parse ranges; potential out-of-bounds parsing.

---

## MEDIUM Findings

### M1. CI/CD Actions Not Pinned to Commit SHAs
**Files:** `.github/workflows/ci.yml`, `.github/workflows/release.yml`

All GitHub Actions use floating version tags:
```yaml
uses: actions/checkout@v4
uses: maxim-lobanov/setup-xcode@v1
uses: softprops/action-gh-release@v1
```

Tag references can be silently moved by upstream maintainers. `maxim-lobanov/setup-xcode` is a third-party action not published by GitHub. A compromised action could exfiltrate `GITHUB_TOKEN` or inject malicious code into builds.

**Recommendation:** Pin to full commit SHAs.

---

### M2. Loose Dependency Version Constraints
**File:** `Package.swift`

```swift
.package(url: "https://github.com/tree-sitter/tree-sitter", from: "0.26.3"),
.package(url: "https://github.com/blaineam/TreeSitterLanguages", from: "2.0.0"),
```

`from:` allows any semver-compatible future version. A compromised or buggy upstream release is automatically pulled in. `TreeSitterLanguages` is a custom fork with a smaller trust boundary.

**Recommendation:** Use `.upToNextMinor(from:)` or pin to exact versions.

---

### M3. `fatalError` Reachable from User Input
**File:** `Sources/Keystone/TextView/SearchAndReplace/ReplacementStringParser.swift:62`

```swift
} else {
    fatalError("We thought we were collecting a placeholder but...")
}
```

This `fatalError` is in the replacement string parsing path, which processes user input from find-and-replace. If parsing logic has an edge case, this crashes the app.

---

### M4. Assertions Used for Security-Critical Invariants
**File:** `Sources/Keystone/RedBlackTree/RedBlackTree.swift` (multiple lines)

`assert()` calls guard tree invariants but are compiled out in Release builds. Violated invariants in production could lead to corrupted tree state and undefined behavior.

---

## Recommendations Summary

| Priority | Action |
|----------|--------|
| **P0** | Fix memory leak in `NSString+Helpers.swift:27` - deallocate buffer on failure |
| **P0** | Fix logic bug in `TreeSitterTextPredicatesEvaluator.swift:64` - use `rhsCaptureIndex` |
| **P0** | Replace force-unwraps in `TreeSitterQuery.swift:59,101` with guard-let |
| **P0** | Add bounds checking to predicate parsing loop in `TreeSitterQuery.swift:76` |
| **P1** | Add null check before `UnsafeBufferPointer` in `TreeSitterTree.swift:26` |
| **P1** | Add ReDoS protection (timeout or pattern complexity limits) for user regex |
| **P1** | Use checked arithmetic for NSRange calculations (`addingReportingOverflow`) |
| **P1** | Validate NSRange bounds against string length before substring operations |
| **P2** | Pin GitHub Actions to commit SHAs |
| **P2** | Tighten SPM dependency version ranges |
| **P2** | Replace `fatalError` with graceful error handling in `ReplacementStringParser` |
| **P2** | Replace security-critical `assert()` calls with `precondition()` or guard statements |
