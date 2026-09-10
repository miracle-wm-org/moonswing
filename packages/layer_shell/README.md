# layer_shell — temporary vendored fork

**This is not our package.** It is a verbatim copy of
[`mattkae/layer_shell.dart`](https://github.com/mattkae/layer_shell.dart) at
commit `51db601`, plus one 38-line addition, carried here only until that
addition lands upstream.

## Why it exists

Flutter `master` turned `BaseWindowControllerLinux` from an `abstract interface
class` with two getters into an `abstract mixin class` carrying real
implementations, and migrated its own controllers from `implements` to `with`.
`LayershellWindowController` still says `implements`, so it now owes five
members it has never heard of:

    setDecorated  setAppPaintable  setBackgroundColor  beginMoveDrag  beginResizeDrag

Nothing outside that package can supply them — Dart has no way to add members to
another package's class — so `flutter test` and `flutter build` fail to compile
`layer_shell` itself, which takes the whole shell down with it. Upstream is at
its default-branch HEAD (`51db601`, the commit `pubspec.lock` already pinned),
so there was no revision to upgrade to either.

`packages/ext_session_lock` needed the same five members for the same reason and
got them in commit `5406a37`; this is the other half of that migration, for the
one package we do not own.

## What was changed

Exactly one hunk, at the end of `LayershellWindowController` in
`lib/layer_shell.dart` — the five members, all no-ops. `diff` against upstream
`51db601` shows nothing else. The `example/`, demo media and CI config are not
copied; only `lib/`, `pubspec.yaml`, `analysis_options.yaml` and `LICENSE` are.

Two details of the spelling are load-bearing, and match `ext_session_lock`:

- **No `@override`.** `snap/snapcraft.yaml` pins a Flutter revision that predates
  these members, where an `@override` on them is an *error*. The missing
  annotation on `master` is only a lint, ignored at each site.
- **`edge` is an `Object`, not a `WindowDragEdge`** — that enum does not exist on
  the pinned revision. Parameter types are contravariant, so a supertype is a
  valid implementation, and nothing reads the value.

## How to remove it

This directory is meant to be deleted. Wiring it in is three lines of
`dependency_overrides` in the root `pubspec.yaml`; the real dependency
declaration still points at the upstream git URL and was never touched.

When the same hunk lands on `mattkae/layer_shell.dart`:

```sh
# 1. delete the `dependency_overrides:` block naming layer_shell from pubspec.yaml
# 2. rm -rf packages/layer_shell
flutter pub upgrade layer_shell
flutter analyze && flutter test
```

`CLAUDE.md`'s rule for this class of break is upstream-first, and that rule still
stands — this fork is the stopgap, not the answer.
