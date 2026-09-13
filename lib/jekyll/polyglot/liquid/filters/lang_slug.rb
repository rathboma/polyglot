module Jekyll
  module Polyglot
    module Liquid
      # Translates a language code into the path segment used for it, as
      # configured by `language_slugs` - e.g. 'pt-BR' becomes 'pt-br'. A
      # language with no slug configured is returned unchanged.
      #
      # Polyglot uses the slug for the URLs it builds itself, but a template
      # that constructs a language URL by iterating `site.languages` would
      # otherwise emit the raw code and link at a path the host redirects
      # away from:
      #
      #   <a href="/{{ lang | lang_slug }}/about">
      module LangSlugFilter
        def lang_slug(lang_code)
          site = @context.registers[:site]
          return lang_code unless site.respond_to?(:lang_slug)

          site.lang_slug(lang_code.to_s)
        end
      end
    end
  end
end

Liquid::Template.register_filter(Jekyll::Polyglot::Liquid::LangSlugFilter)
