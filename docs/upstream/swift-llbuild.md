# Changes for swiftlang/swift-llbuild

Swift Build and SwiftPM require swift-llbuild on branch `release/6.4.x`, at `ab642120`. nomac
depends on the owner's fork (`khzouroussama/swift-llbuild`) with the same requirement, which
replaces theirs: its `release/6.4.x` and `release/6.4.1-linux-fixes` are `b0afd154`, that revision
with exactly the change below, which applies with `git apply` to it (ADR 0002). Proposing it
upstream is the owner's decision.

## 1. A directory entry whose status cannot be read

Patch: `.github/upstream/swift-llbuild/0001-directory-contents-unreadable-entry.patch`.

**Problem.** `DirectoryContentsTask::getContents` (`lib/BuildSystem/BuildSystem.cpp`) asks each
entry's status to skip symbolic links to a parent folder, and dereferences the `ErrorOr` without
checking it. An entry removed between reading the directory and reading its status aborts a debug
build (`Assertion '!HasError && "Cannot get value when an error exists!"' failed`), and a release
build reads an undefined value.

**Change.** An entry whose status cannot be read is listed, as a file is.

**Evidence.** nomac's RN sweep: expo-with-maps aborted there once, and built in the next run.
