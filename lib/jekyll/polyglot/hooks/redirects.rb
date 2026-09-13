# frozen_string_literal: true

# Hook to localize Netlify _redirects file for multilingual sites.
# When enabled, generates language-prefixed versions of each redirect.
#
# Configuration:
#   localize_redirects: true  # Enable the feature
#   exclude_from_redirect_localization:  # Optional: paths to skip
#     - /signin
#     - /app
#
# Example:
#   Input:  /github https://github.com/org/repo 302
#   Output: /github https://github.com/org/repo 302
#           /es/github https://github.com/org/repo 302
#           /de/github https://github.com/org/repo 302
#           ...

Jekyll::Hooks.register :polyglot, :post_write do |site|
  hook_redirects(site)
end

# True when a redirect source already sits under one of the site's languages.
# Checks both the slug (what the path actually is) and the language code, since
# a hand-written rule may use either when language_slugs maps them apart.
def already_language_prefixed?(site, source)
  site.languages.any? do |lang|
    ["/#{site.lang_slug(lang)}", "/#{lang}"].uniq.any? do |prefix|
      source.start_with?("#{prefix}/") || source == prefix
    end
  end
end

def hook_redirects(site)
  return unless site.config.fetch('localize_redirects', false)

  redirects_path = File.join(site.source, '_redirects')
  return unless File.exist?(redirects_path)

  exclusions = site.config.fetch('exclude_from_redirect_localization', [])
  lines = File.readlines(redirects_path)
  localized_lines = []

  lines.each do |line|
    # Always include the original line
    localized_lines << line

    # Skip comments and empty lines
    stripped = line.strip
    next if stripped.empty? || stripped.start_with?('#')

    # Parse the redirect line: /source /target [status_code]
    parts = stripped.split(/\s+/)
    next if parts.length < 2

    source = parts[0]

    # Skip if source is in exclusion list
    next if exclusions.include?(source)

    # Only process paths that start with /
    next unless source.start_with?('/')

    # Skip if source already has a language prefix
    next if already_language_prefixed?(site, source)

    # Add localized versions for non-default languages
    site.languages.each do |lang|
      next if lang == site.default_lang

      # Paths use the slug, not the language code - a rule written with the
      # code would point at a URL the host redirects away from.
      slug = site.lang_slug(lang)
      localized_source = "/#{slug}#{source}"
      destination = parts[1]

      # Localize destination if it's an internal path (starts with /)
      # but not if it's an external URL (contains ://)
      localized_destination = if destination.start_with?('/') && !destination.include?('://')
                                "/#{slug}#{destination}"
                              else
                                destination
                              end

      rest = parts[2..-1]&.join(' ') || ''
      rest = " #{rest}" unless rest.empty?
      localized_lines << "#{localized_source} #{localized_destination}#{rest}\n"
    end
  end

  # Write to destination
  dest_path = File.join(site.dest, '_redirects')
  File.write(dest_path, localized_lines.join)
end
