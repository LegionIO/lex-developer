# Changelog

## [0.1.1] - 2026-04-22

### Fixed
- Add missing `Runners::Feedback` module; resolves `NameError: uninitialized constant` during actor subscription prepare
- Add `include Legion::Extensions::Helpers::Lex` to all runner modules (`Developer`, `Ship`, `Feedback`)
