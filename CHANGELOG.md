# Changelog

All notable changes to jekyll-polyglot are documented here.

## Unreleased

### Added
- `generate_fallback_pages` config option (default `true`, backwards compatible). When set to
  `false`, a language pass only approves documents whose own language matches - no
  default-language body is generated under a localised URL for a translation that doesn't
  exist. See README ("Disabling Fallback Pages").
