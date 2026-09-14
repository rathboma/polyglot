# The half of the Jekyll::Site patch that deals with the language a page is
# actually rendered in.
#
# Polyglot builds one copy of the site per language, and serves a page that has
# no translation for the language being built as fallback content in another
# language.  These methods localize site.data per language and let a fallback
# page borrow the language of its own content for the duration of its render,
# so it can come out as a complete copy of that page rather than a mix of two
# languages.  See the full_default_lang_fallback option in the README.
module Jekyll
  class Site
    # Merges the language specific subtrees of site.data into site.data itself,
    # favouring the active_lang, then the default_lang, then any data that is
    # not language specific.
    def localize_data
      @unlocalized_data = @data
      @localized_data_cache = {}
      @rendered_lang_stash = nil
      assign_data(build_localized_data(@active_lang))
    end

    # site.data as it would have been built if lang were the active language.
    # Fallback pages are rendered with the data of the language their content
    # is written in, which is not always the language being built.
    def localized_data_for(lang)
      return @data if lang.nil? || lang == @active_lang

      @localized_data_cache ||= {}
      @localized_data_cache[lang] ||= build_localized_data(lang)
    end

    def build_localized_data(lang)
      localized = merge_lang_data(@unlocalized_data || @data, @default_lang)
      localized = merge_lang_data(localized, lang) unless lang == @default_lang
      localized
    end

    # recursively merges the lang subtree of data over the rest of data
    # See: https://www.ruby-forum.com/topic/142809
    def merge_lang_data(data, lang)
      key = data.keys.find { |k| k.to_s.downcase == lang.to_s.downcase }
      return data unless data[key].is_a?(Hash)

      data.merge(data[key], &data_merger)
    end

    def data_merger
      @data_merger ||= proc do |_key, v1, v2|
        v1.is_a?(Hash) && v2.is_a?(Hash) ? v1.merge(v2, &data_merger) : v2
      end
    end

    # swaps the hash behind site.data.  Jekyll memoizes the copy it hands to
    # liquid separately, so both have to be replaced together.
    def assign_data(data)
      @data = data
      @site_data = config['data'] || data
    end

    # true when doc is being rendered in a language other than the one the site
    # is being built for, which means it is fallback content
    def fallback_page?(doc)
      lang = doc.data['rendered_lang']
      !lang.nil? && lang != @active_lang
    end

    # Points the language dependent site variables at the language doc is
    # actually written in for the duration of its render, so a fallback page
    # comes out as a complete copy of the page in that language instead of a
    # mix of both.  Does nothing unless full_default_lang_fallback is enabled.
    def use_rendered_lang(doc, payload)
      restore_active_lang
      return unless @full_default_lang_fallback && fallback_page?(doc)

      rendered_lang = doc.data['rendered_lang']
      @rendered_lang_stash = { 'payload' => payload, 'data' => @data }
      assign_payload_lang(payload, rendered_lang)
      assign_data(localized_data_for(rendered_lang))
    end

    # undoes use_rendered_lang once the document and its layouts are rendered
    def restore_active_lang
      stash = @rendered_lang_stash
      return if stash.nil?

      @rendered_lang_stash = nil
      assign_payload_lang(stash['payload'], @active_lang)
      assign_data(stash['data'])
    end

    def assign_payload_lang(payload, lang)
      payload['site']['active_lang'] = lang
      lang_vars.each do |v|
        payload['site'][v] = lang
      end
    end
  end
end
