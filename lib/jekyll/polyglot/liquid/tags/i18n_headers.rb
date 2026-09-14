module Jekyll
  module Polyglot
    module Liquid
      class I18nHeadersTag < ::Liquid::Tag
        def initialize(tag_name, text, tokens)
          super
          @url = text
          @url.strip!
          @url.chomp! '/'
        end

        def render(context)
          site = context.registers[:site]
          page = context.registers[:page]
          permalink = page['permalink'] || page['url'] || ''
          # Strip the language prefix from the permalink for matching (e.g. /es/about -> /about),
          # whether it carries the language code or its lang_urls segment
          normalized_permalink = site.delocalize_permalink(permalink, site.active_lang)
          page_id = page['page_id']
          permalink_lang = page['permalink_lang']
          baseurl = site.config['baseurl'] || ''
          site_url = @url.empty? ? site.config['url'] + baseurl : @url
          i18n = ""

          # Find all documents and pages that are translations of this page
          # Match by page_id if set, otherwise match by permalink
          all_content = site.collections.values.flat_map(&:docs) + site.pages
          docs_with_same_id = if page_id
            all_content
              .filter { |doc| !doc.data['page_id'].nil? }
              .select { |doc| doc.data['page_id'] == page_id }
          else
            # No page_id, match by permalink instead
            # Use normalized permalink to handle language prefixes
            all_content
              .filter { |doc| !doc.data['permalink'].nil? }
              .select { |doc| doc.data['permalink'] == normalized_permalink }
          end

          # Build a hash of lang => permalink for all matching docs in configured
          # languages (language codes are case sensitive, see Site#unconfigured_lang_allowed?)
          # If lang is not set, assume it's the default language
          lang_to_permalink = docs_with_same_id
            .reject { |doc| doc.data['lang'] && !site.all_languages.include?(doc.data['lang']) }
            .to_h { |doc| [doc.data['lang'] || site.default_lang, doc.data['permalink']] }

          # Determine if this page has an actual translation for the active language
          current_lang = site.active_lang
          has_translation_for_current_lang = lang_to_permalink[current_lang] || (permalink_lang && permalink_lang[current_lang])

          # Canonical URL logic:
          # - If page has actual translation for current lang: canonical points to current lang URL
          # - If page is fallback AND fallback_canonical_to_default_lang is enabled: canonical points to default lang URL
          # - Otherwise: canonical points to current lang URL (backwards compatible)
          current_permalink = lang_to_permalink[current_lang] || (permalink_lang && permalink_lang[current_lang]) || normalized_permalink
          current_permalink = "/#{current_permalink}" unless current_permalink.start_with?("/")

          use_default_lang_canonical = site.fallback_canonical_to_default_lang && !has_translation_for_current_lang && current_lang != site.default_lang

          canonical_permalink = if use_default_lang_canonical
            # Fallback page with option enabled: point to default language URL
            default_permalink = lang_to_permalink[site.default_lang] || (permalink_lang && permalink_lang[site.default_lang]) || normalized_permalink
            default_permalink = "/#{default_permalink}" unless default_permalink.start_with?("/")
            default_permalink
          else
            # The default language is served at the root, every other language
            # under its url segment (unless the permalink already carries it)
            site.localize_permalink(current_permalink, current_lang)
          end
          # Site#assignCanonicalUrl works out the same url from the full set of
          # translations, including the ones this build dropped, so prefer it
          # whenever it is available and this tag was not given an explicit url
          canonical_href = if @url.empty? && !page['canonical_url'].to_s.empty?
            page['canonical_url']
          else
            "#{site_url}#{canonical_permalink}"
          end
          i18n += "<link rel=\"canonical\" href=\"#{canonical_href}\"/>\n"

          # Get the default language permalink for x-default
          default_lang_permalink = lang_to_permalink[site.default_lang] || (permalink_lang && permalink_lang[site.default_lang]) || normalized_permalink
          default_lang_permalink = "/#{default_lang_permalink}" unless default_lang_permalink.start_with?("/")

          site.languages.each do |lang|
            alt_permalink = lang_to_permalink[lang] || (permalink_lang && permalink_lang[lang]) || normalized_permalink
            alt_permalink = "/#{alt_permalink}" unless alt_permalink.start_with?("/")

            # Skip hreflang for this language if no actual translation exists
            # Only generate hreflang tags for languages that have real translated content
            has_translation = lang_to_permalink[lang] || (permalink_lang && permalink_lang[lang])
            next if !has_translation && lang != site.default_lang

            i18n += if lang == site.default_lang
              "<link rel=\"alternate\" hreflang=\"#{lang}\" href=\"#{site_url}#{alt_permalink}\"/>\n" \
                "<link rel=\"alternate\" hreflang=\"x-default\" href=\"#{site_url}#{default_lang_permalink}\"/>\n"
            else
              # For non-default languages, serve the language-specific permalink under
              # the language url segment (unless the permalink already carries it)
              lang_permalink = site.localize_permalink(alt_permalink, lang)
              "<link rel=\"alternate\" hreflang=\"#{lang}\" href=\"#{site_url}#{lang_permalink}\"/>\n"
            end
          end
          i18n
        end
      end
    end
  end
end

Liquid::Template.register_tag('I18n_Headers', Jekyll::Polyglot::Liquid::I18nHeadersTag)
Liquid::Template.register_tag('i18n_headers', Jekyll::Polyglot::Liquid::I18nHeadersTag)
