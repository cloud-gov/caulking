// Module for cloud-gov/caulking.
//
// This repository provides global git hooks and reusable pre-commit hooks, not a
// Go application. This go.mod exists for ONE reason: pre-commit's `language: golang`
// support always runs `go install ./...` in the hook-repo root before installing a
// hook's `additional_dependencies` (see pre-commit languages/golang.py). Without a
// go.mod that command errors ("directory prefix . does not contain main
// module"), which breaks every repo:local `language: golang` hook (such as the
// *-selfcontained Go hooks) in a clean Linux/CI/container sandbox.
//
// This module intentionally declares NO packages and NO require block:
//   * `go install ./...` becomes a clean no-op (exit 0, "matched no packages").
//   * Tool versions remain SINGLE-SOURCED in each hook's `additional_dependencies`
//     in .pre-commit-hooks.yaml — there is deliberately no tools.go / require list
//     here to drift against them.
//
// Do NOT add dependencies here. Bump tool versions in .pre-commit-hooks.yaml.
module github.com/cloud-gov/caulking

go 1.24
