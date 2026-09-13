# Changelog

All notable changes to jekyll-polyglot are documented here.

## Unreleased

### Added
- `generate_fallback_pages` config option (default `true`, backwards compatible). When set to
  `false`, a language pass only approves documents whose own language matches - no
  default-language body is generated under a localised URL for a translation that doesn't
  exist. See README ("Disabling Fallback Pages").
- `canonical_url` is now published as document data on every page/post, computed from each
  document's own URL and prefixed with its language pass (or unprefixed for the default
  language). This lets jekyll-seo-tag's `<link rel="canonical">` and `og:url` agree with
  `{% I18n_Headers %}`, since jekyll-seo-tag already reads `page['canonical_url']`. Front
  matter that sets `canonical_url` explicitly is never overwritten. Pages created by
  generators (jekyll-archives category pages, for example) are covered too: Jekyll runs
  generators after the `:site, :post_read` hook, so those pages are assigned `canonical_url`
  and `rendered_lang` at `:site, :pre_render` instead. See README ("Canonical URL as document
  data").
- `language_slugs` config option to map a language code to a different output path segment,
  e.g. `{ "pt-BR": "pt-br" }`. The code is still used for `_data/` lookup, `hreflang` and
  `<html lang>`; only the URL path (output directory, relativized links, `canonical_url`,
  and the rules `localize_redirects` generates) uses the slug. Fixes language codes whose
  casing doesn't survive being served as a path (hosts that lower-case paths, e.g. `pt-BR`
  -> `pt-br`) previously 301ing every emitted URL for that language. See README ("Separating
  Language Code from URL Slug").
