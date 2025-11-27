# OpenAI Swift SDK - What's New (9 Commits Behind)

**Generated:** 2025-11-28
**Commits Analyzed:** fa40cdc, 4ed3ea9, 208a2a8, e3d1767, 2ca651b, 9fd5a2c, 6381909, 28884fc, 444fb5d
**Date Range:** 2025-10-21 to 2025-11-28

---

## Summary of Changes

### 1. New GPT-5.1 Models Support (PR #393)
**Author:** Neel Virdy
**Files Changed:** `Models.swift`, `README.md`

Added support for two new GPT-5.1 model variants:
- `gpt-5.1` - Enhanced version of GPT-5 with improved reasoning and performance
- `gpt-5.1-chat-latest` - Latest GPT-5.1 model optimized for chat interactions

Both models are added to `allChatModels` and `allResponsesModels` arrays.

### 2. ReasoningEffort.none Support (PR #393)
**Author:** Neel Virdy
**Files Changed:** `ChatQuery.swift`, `Components.swift`, `OpenAITestsDecoder.swift`

Added `none` as a valid value for `ReasoningEffort` enum:
- Previously supported: `minimal`, `low`, `medium`, `high`
- Now supported: `none`, `minimal`, `low`, `medium`, `high`

This allows disabling reasoning entirely for reasoning-capable models.

### 3. Verbosity Support for Responses API (PR #395)
**Author:** Neel Virdy
**Files Changed:** `CreateModelResponseQuery+TextResponseConfigurationOptions.swift`, `OpenAITestsDecoder.swift`

Added `verbosity` parameter to `TextResponseConfigurationOptions`:
- New enum `Verbosity` with values: `low`, `medium`, `high`
- Updated `init(format:verbosity:)` to accept optional verbosity
- Added `Decodable` conformance to `OutputFormat` enum (previously only `Encodable`)

**Usage:**
```swift
let query = CreateModelResponseQuery(
    input: .textInput("Return a low verbosity response."),
    model: .gpt5,
    text: .init(format: .text, verbosity: .low)
)
```

### 4. JSON Schema Numeric Constraints Fix (PR #391)
**Author:** mi12-root
**Files Changed:** `JSONDocument.swift`, `JSONSchemaField.swift`

**Bug Fix:** Fixed `multipleOf` function that was incorrectly using "maximum" as the keyword instead of "multipleOf".

**New Overloads:** Added `Double` and `Int` overloads for numeric JSON schema constraints:
- `multipleOf(_ value: Double/Int)`
- `maximum(_ value: Double/Int)`
- `exclusiveMaximum(_ value: Double/Int)`
- `minimum(_ value: Double/Int)`
- `exclusiveMinimum(_ value: Double/Int)`

Also added `Double` conformance to `JSONDocument` protocol.

---

## Risk Assessment

### Low Risk Changes

| Change | Risk Level | Reason |
|--------|------------|--------|
| GPT-5.1 models | **Low** | Additive only - new model constants, no breaking changes |
| ReasoningEffort.none | **Low** | Additive enum case, existing code unaffected |
| JSON Schema overloads | **Low** | Additive convenience methods, existing `Decimal` versions unchanged |

### Medium Risk Changes

| Change | Risk Level | Reason |
|--------|------------|--------|
| Verbosity support | **Medium** | Adds new property to existing struct, but optional with default nil |
| OutputFormat Decodable | **Medium** | Adds decoder implementation - should be tested for compatibility |

### Bug Fix (Important)

| Change | Risk Level | Reason |
|--------|------------|--------|
| `multipleOf` keyword fix | **Low-Medium** | Fixes a bug where "maximum" was used instead of "multipleOf". If your code relies on the buggy behavior (unlikely), this could be breaking |

---

## Merge Recommendation

**Overall Risk: LOW**

### Reasons to Merge:
1. All changes are additive or bug fixes
2. No breaking API changes to existing functionality
3. New features (GPT-5.1, verbosity) may be useful
4. Bug fix in `multipleOf` corrects incorrect behavior
5. Tests have been added for new functionality

### Pre-Merge Checklist:
- [ ] Build the project to verify no compilation errors
- [ ] Run existing tests to ensure no regressions
- [ ] Verify any code using `JSONSchemaField.multipleOf()` works correctly after the bug fix
- [ ] Test any existing Responses API usage with the new optional `verbosity` parameter

### Recommended Merge Command:
```bash
cd thirdparty/OpenAI
git merge origin/main
```

---

## Files Changed Summary

| File | Lines | Type |
|------|-------|------|
| `README.md` | +5/-1 | Documentation |
| `JSONDocument.swift` | +1 | Feature |
| `JSONSchemaField.swift` | +42 | Feature + Bug Fix |
| `ChatQuery.swift` | +7/-1 | Feature |
| `Models.swift` | +12/-1 | Feature |
| `CreateModelResponseQuery+TextResponseConfigurationOptions.swift` | +49 | Feature |
| `Components.swift` | +3/-1 | Feature |
| `OpenAITestsDecoder.swift` | +98 | Tests |

**Total: +205 lines, -12 lines**
