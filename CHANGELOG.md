# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial extraction from [Aletheia](https://hex.pm/packages/aletheia):
  term representation, clause database, SLD-resolution engine (with a
  genuine clause-scoped cut), and the arithmetic/exceptions/lists/io
  builtin predicates, split out into their own package so they're
  usable without Aletheia's reader/syntax layer.
