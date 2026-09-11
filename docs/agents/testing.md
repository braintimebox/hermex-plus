# Testing Notes

Failure modes observed in *this* suite, with the commit that fixed each one. The
suite is a gate (see `CONVENTIONS.md` §3), so a test that asserts the wrong thing
is worse than a missing test: it passes, it looks like coverage, and it hides the
behaviour it was supposed to pin.

Read this before adding a test that touches timing, caching, or a request list.
Every entry below was green in review and wrong in fact, and none of them would
have been caught by a coverage threshold — the tests existed.

---

## 1. Asserting call order across `async let`

**What happened.** `testComposerConfigurationUsesSessionProfileDefaultBeforeSending`
asserted the literal sequence
`[profiles, profile/switch, models, reasoning, workspaces, commands, chat/start]`.

`/api/reasoning` (model-scoped) and `/api/workspaces` (independent) are issued
with `async let` and awaited together:

```swift
async let reasoningTask = client.reasoning(...)
let workspaceResponse = try await workspacesTask
let reasoningResponse = try await reasoningTask
```

Which one reaches the client first is not defined. CI produced
`workspaces` before `reasoning` and failed.

**Rule.** When calls are concurrent, assert the **set** of endpoints, then assert
only the orderings the code actually guarantees — a dependency that must settle
first, or something that is last because a later step triggers it.

```swift
XCTAssertEqual(Set(requestPaths), Set([...]))
let switchIndex = try XCTUnwrap(requestPaths.firstIndex(of: "/api/profile/switch"))
let modelsIndex = try XCTUnwrap(requestPaths.firstIndex(of: "/api/models"))
XCTAssertLessThan(switchIndex, modelsIndex, "the profile switch must settle before the catalog is fetched")
```

**Why it looked fine.** While the composer config cache was answering, a later
pass returned early and never exercised the parallel pair, so the sequence held
by accident. Removing the cache exposed the race (fixed in `ba784b8`, `0086f70`).

---

## 2. Reading a cache on the line after an async write

**What happened.** `ChatViewModel` persists transcripts on a background queue:

```swift
DispatchQueue.global(qos: .utility).async {
    let bgContext = ModelContext(container)
    try CacheStore.cacheMessages(...)
}
```

Tests asserted the cache contents immediately after `loadMessages` /
`sendMessage` / `cacheCompletedResponse` returned. The write had not landed, so
the read returned the previous contents — or `[]` on a fresh context.

Failed with `("[]") is not equal to ("["Keep working"]")` and
`("["Stale cached answer"]") is not equal to ("["Fresh question", "Fresh answer"]")`.
Both read as logic bugs in the code under test.

**Rule.** After triggering a background write, wait for the contents to appear:

```swift
try await waitUntil("the reconciled transcript to land in the cache") {
    let contents = (try? CacheStore.cachedMessages(
        serverURL: serverURL, sessionID: sessionID, in: context
    ))?.compactMap(\.content) ?? []
    return contents == ["Keep working", "Recovered transcript."]
}
```

When a test triggers **several** writes, wait for the **final** state. Waiting for
the first one that appears (`contents == ["Keep working"]`) can return on the
intermediate state and then be asserted against after a later write lands.

---

## 3. A helper that times out silently

**What happened.** `ChatViewModelSendTests.waitUntil` looped 40 × 50ms and then
returned when the condition never became true. The test continued to its next
assertion and failed with whatever the state happened to be at that moment.

Consequence: **every** timing-sensitive failure in that file was reported as a
data problem (`"[]" is not equal to "["Keep working"]"`), and was mis-diagnosed
as a cache bug for several CI runs. The real cause was the wait expiring.

**Rule.** A timeout is a failure, and it must say what it was waiting for:

```swift
XCTFail("timed out after \(timeout)s waiting for: \(description)", file: file, line: line)
```

Pass a description at the call site — `waitUntil("the optimistic message to be
persisted") { ... }`. A silent expiring wait turns a timing problem into a
plausible-looking logic problem, which is the expensive kind.

**Budget.** The default here is 10s, not 2s. A background cache write contends
with the main context for SwiftData; 2s of 50ms sleeps was not reliably enough
on CI.

---

## 4. Waiting on a signal that fires before the condition

**What happened.** `testTransportErrorChecksStatusAndFinishesWhenStreamIsInactive`
waited on `didRequestStatus && didReloadMessages` — flags the mock sets as each
response is served. The view model clears `activeStreamID` *after* those
responses, so `XCTAssertNil(viewModel.activeStreamID)` ran mid-flight and saw
`"stream-123"` still set.

**Rule.** Wait on the state the test is about, not on an earlier side effect that
is convenient to observe:

```swift
try await waitUntil("the inactive stream to clear activeStreamID") {
    viewModel.activeStreamID == nil && didReloadMessages
}
```

Request flags are a proxy for "the mock was called". They are not a proxy for
"the view model finished reacting".

---

## 5. Asserting a call count that the design deliberately changed

**What happened.** `testComposerConfigurationReloadDoesNotOverwriteConcurrentWorkspaceSelection`
asserted `profileRequests.count == 2`, i.e. a second network round trip after the
state changed. The loader serves that pass from its process-wide memory cache —
that is what the cache is for.

**Rule.** Before asserting a count, ask what the count is a proxy for, and
whether the design is allowed to change it. If the property is "the loader does
not skip the network entirely", assert `>= 1`, and keep the assertion that names
the actual subject of the test.

---

## 6. Process-global caches leaking between test classes

**What happened.** `ChatComposerConfigLoader.memoryCache` is `static`, 24h TTL,
unkeyed. That is right for the app (iOS keeps the process alive across
background/foreground) and wrong under test: the first class to load a
configuration populated state every later class then read. Failures looked like
product bugs — `testSelectedModelTitle…` expected `"OpenAI Shared"` and got
`"model"`, because the catalog came from a different test.

**Rule.** Two layers, and prefer the second:

1. Bypass — under test the cache is skipped entirely
   (`ChatComposerConfigLoader.isRunningTests`). This removes the possibility
   rather than managing it.
2. Reset — `resetProcessGlobalTestState()` from `setUp`. Needed for real state
   that cannot be bypassed, such as the cache-store maintenance throttle.

A reset that every class must remember is a reset that one class will forget.
Prefer the bypass, and say in the comment why the cache exists in the first
place, so the next person does not "fix" the bypass.

---

## 7. Assuming a literal list when the code tolerates a set

**What happened.** `testLoadReturnsPartialStateAndStillRefreshesCommandsWhenConfigurationFails`
expected `[profiles, models, commands]` while `/api/models` returned 500.
`/api/workspaces` is issued in parallel with the reasoning call, so it fires
regardless — and `/api/reasoning` is **not** issued at all, because it is scoped
to a model that failed to load.

**Rule.** Assert the endpoints that are actually reached, and make the interesting
absence explicit:

```swift
XCTAssertFalse(requestPaths.contains("/api/reasoning"),
               "reasoning needs a model, and models failed")
```

"When X fails, Y must not be attempted" is a real contract. Write it as that,
rather than encoding it in a coincidental list order.

---

## Adding a test for new behaviour

Not required by any gate — there is no coverage threshold in this repo. But if you
add behaviour in `HermesMobile/` that has a testable shape, add the test in the
same commit; a test written a week later asserts what the code does, not what it
was supposed to do.

Before committing, run the suite. If a test you did not touch fails, assume it is
telling you something about your change — six of the eight fixes above were found
that way.
