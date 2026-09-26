import os

/// Unified logging. Read it with:
///   /usr/bin/log show --last 10m --predicate 'subsystem == "nl.vincentbruijn.mould"' --style compact
/// (plain `log` in zsh is a shell builtin, hence the full path).
let log = Logger(subsystem: "nl.vincentbruijn.mould", category: "app")
