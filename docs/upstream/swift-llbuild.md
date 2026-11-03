# Changes for swiftlang/swift-llbuild

nomac gets llbuild through Swift Build (`release/6.4.x`, `ab642120` in `Package.resolved`). The
change below is not applied: applying it needs a fork of swift-llbuild (BACKLOG B-137), and
proposing it upstream is the owner's decision. It applies with `git apply` to that revision.

## 1. A directory entry whose status cannot be read

Patch: `.github/upstream/swift-llbuild/0001-directory-contents-unreadable-entry.patch`.

**Problem.** `DirectoryContentsTask::getContents` (`lib/BuildSystem/BuildSystem.cpp`) asks each
entry's status to skip symbolic links to a parent folder, and dereferences the `ErrorOr` without
checking it. An entry removed between reading the directory and reading its status aborts a debug
build (`Assertion '!HasError && "Cannot get value when an error exists!"' failed`), and a release
build reads an undefined value.

**Change.** An entry whose status cannot be read is listed, as a file is.

**Evidence.** nomac's RN sweep: expo-with-maps aborted there once, and built in the next run.
