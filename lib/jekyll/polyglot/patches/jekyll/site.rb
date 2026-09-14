require 'English'
require 'etc'

include Process
module Jekyll
  class Site
    attr_reader :default_lang, :languages, :exclude_from_localization, :lang_vars, :lang_from_path, :fallback_canonical_to_default_lang, :serial_default_lang, :lang_urls, :unconfigured_lang, :full_default_lang_fallback
    attr_accessor :file_langs, :active_lang

    def prepare
      @file_langs = {}
      fetch_languages
      @parallel_localization = config.fetch('parallel_localization', true)
      # When true (and parallel_localization is also true), the default
      # language is processed synchronously in the parent before any forks
      # are spawned for the other languages. This makes parallel builds
      # safe for plugins that do expensive one-time setup and share state
      # across the site (e.g. jekyll-assets), which otherwise race when
      # every fork runs that setup at once. See README for details.
      @serial_default_lang = config.fetch('serial_default_lang', false)
      @lang_from_path = config.fetch('lang_from_path', false)
      @fallback_canonical_to_default_lang = config.fetch('fallback_canonical_to_default_lang', false)
      # When true, a page that has no translation for the language being built
      # is rendered as a complete copy of the page in the language its content
      # is actually written in, instead of default language content wrapped in
      # site chrome from the language being built. See README for details.
      @full_default_lang_fallback = config.fetch('full_default_lang_fallback', false)
      # what happens to a document whose language is not one of the configured
      # languages, see unconfigured_lang_allowed?
      @unconfigured_lang = config.fetch('unconfigured_lang', 'generate').to_s
      unless %w[error ignore generate].include?(@unconfigured_lang)
        raise Jekyll::Errors::InvalidConfigurationError, "Polyglot: unconfigured_lang must be one of error, ignore or generate, got '#{@unconfigured_lang}'"
      end

      @exclude_from_localization = config.fetch('exclude_from_localization', []).map do |e|
        if File.directory?(e) && e[-1] != '/'
          "#{e}/"
        else
          e
        end
      end
    end

    def fetch_languages
      @default_lang = config.fetch('default_lang', 'en')
      @languages = config.fetch('languages', ['en']).uniq

      fetch_lang_urls
      # the sublanguage sites are written into their url segments, which the
      # default language build must not clean up
      @keep_files += (@languages - [@default_lang]).map { |lang| lang_url(lang) }
      @active_lang = @default_lang
      @lang_vars = config.fetch('lang_vars', [])
    end

    # Reads the optional lang_urls config, a mapping of language code to the
    # url path segment that language is served under:
    #   lang_urls:
    #     pt-BR: pt-br
    # builds the pt-BR site into /pt-br/ and writes /pt-br/ into every url,
    # while site.active_lang, hreflang tags and front matter keep using pt-BR.
    # Languages without an entry are served under their own language code.
    def fetch_lang_urls
      @lang_urls = all_languages.to_h { |lang| [lang, lang] }
      overrides = config.fetch('lang_urls', nil) || {}
      raise Jekyll::Errors::InvalidConfigurationError, "Polyglot: lang_urls must map language codes to url segments, got #{overrides.inspect}" unless overrides.is_a?(Hash)

      overrides.each do |lang, url|
        lang = lang.to_s
        segment = url.to_s.strip.gsub(%r{\A/+|/+\z}, '')
        raise Jekyll::Errors::InvalidConfigurationError, "Polyglot: lang_urls entry '#{lang}' is not one of the configured languages #{all_languages.inspect}#{case_hint(lang)}" unless @lang_urls.key?(lang)
        raise Jekyll::Errors::InvalidConfigurationError, "Polyglot: lang_urls entry '#{lang}' has an empty url segment" if segment.empty?

        @lang_urls[lang] = segment
      end

      # two sublanguage sites written into the same directory would overwrite
      # each other, so refuse to build
      duplicates = (@languages - [@default_lang]).map { |lang| @lang_urls[lang] }.tally.select { |_, count| count > 1 }.keys
      raise Jekyll::Errors::InvalidConfigurationError, "Polyglot: lang_urls maps more than one language to #{duplicates.inspect}" unless duplicates.empty?
    end

    # The url path segment a language is served under: its lang_urls entry
    # when configured, and the language code itself otherwise
    def lang_url(lang)
      @lang_urls.fetch(lang, lang)
    end

    # Every segment a language may appear as in a url: the language codes
    # and, where they differ, their lang_urls segments
    def lang_url_segments
      (@languages || []).flat_map { |lang| [lang, lang_url(lang)] }.uniq
    end

    # The prefixes a permalink may carry for a language: its url segment and,
    # when that differs, the language code itself
    def lang_url_prefixes(lang)
      [lang_url(lang), lang].uniq.map { |segment| "/#{segment}/" }
    end

    # Every language the site builds: the default language and the configured
    # languages
    def all_languages
      ([@default_lang] + @languages).uniq
    end

    # Language codes are case sensitive and must match the configured languages
    # exactly. A document declaring a language the site is not configured for
    # is a typo, a mis-cased code or a language the site does not build, and
    # the unconfigured_lang option decides what happens to it:
    #   generate - build the document regardless, as older polyglot versions
    #              did (the default, for compatibility with them)
    #   ignore   - warn and leave the document out of every language build
    #   error    - fail the build naming the file and the code
    # Returns whether the document may be built with the given language.
    def unconfigured_lang_allowed?(doc, lang, attribute = 'lang')
      return true if all_languages.include?(lang)

      problem = "#{attribute} '#{lang}' which is not one of the configured languages #{all_languages.inspect}#{case_hint(lang)}"
      case @unconfigured_lang
      when 'error'
        raise Jekyll::Errors::FatalException, "Polyglot: #{doc.relative_path} has #{problem}"
      when 'ignore'
        Jekyll.logger.warn "Polyglot:", "Ignoring #{doc.relative_path}'s #{problem}"
        false
      else
        Jekyll.logger.debug "Polyglot:", "Generating #{doc.relative_path} despite its #{problem}"
        true
      end
    end

    # names the configured language a mis-cased code was probably meant to be
    def case_hint(lang)
      meant = all_languages.find { |configured| configured.casecmp?(lang.to_s) }
      meant ? ", did you mean '#{meant}'? Language codes are case sensitive" : ''
    end

    alias process_orig process
    def process
      prepare
      all_langs = all_languages
      if @parallel_localization
        if @serial_default_lang
          # Run the default language in the parent first to prime shared
          # state (e.g. jekyll-assets' Sprockets cache) before forking
          # for the remaining languages.
          process_language @default_lang
          langs_to_fork = @languages - [@default_lang]
        else
          langs_to_fork = all_langs
        end
        nproc = Etc.nprocessors
        pids = {}
        begin
          langs_to_fork.each do |lang|
            pids[lang] = fork do
              process_language lang
            end
            while pids.length >= (lang == langs_to_fork[-1] ? 1 : nproc)
              sleep 0.1
              pids.map do |pid_lang, pid|
                next unless waitpid pid, Process::WNOHANG

                pids.delete pid_lang
                raise "Polyglot subprocess #{pid} (#{lang}) failed (#{$CHILD_STATUS.exitstatus})" unless $CHILD_STATUS.success?
              end
            end
          end
        rescue Interrupt
          langs_to_fork.each do |lang|
            next unless pids.key? lang

            puts "Killing #{pids[lang]} : #{lang}"
            kill('INT', pids[lang])
          end
        end
      else
        all_langs.each do |lang|
          process_language lang
        end
      end
      Jekyll::Hooks.trigger :polyglot, :post_write, self
    end

    alias site_payload_orig site_payload
    def site_payload
      payload = site_payload_orig
      payload['site']['default_lang'] = default_lang
      payload['site']['languages'] = languages
      payload['site']['active_lang'] = active_lang
      # build_lang always reports the language the site is being built for, even
      # on a fallback page where active_lang follows the page's rendered_lang.
      payload['site']['build_lang'] = active_lang
      payload['site']['lang_urls'] = lang_urls
      lang_vars.each do |v|
        payload['site'][v] = active_lang
      end
      payload
    end

    def process_language(lang)
      @active_lang = lang
      config['active_lang'] = @active_lang
      config['build_lang'] = @active_lang
      lang_vars.each do |v|
        config[v] = @active_lang
      end
      if @active_lang == @default_lang
      then process_default_language
      else
        process_active_language
      end
    end

    def process_default_language
      old_include = @include
      process_orig
      @include = old_include
    end

    def process_active_language
      old_dest = @dest
      old_exclude = @exclude
      @file_langs = {}
      @dest = "#{@dest}/#{lang_url(@active_lang)}"
      @exclude += @exclude_from_localization
      process_orig
      @dest = old_dest
      @exclude = old_exclude
    end

    def split_on_multiple_delimiters(string)
      delimiters = ['.', '/']
      regex = Regexp.union(delimiters)
      string.split(regex)
    end

    # Convert glob pattern to regex pattern
    # * matches any characters except /
    # ? matches any single character except /
    def glob_to_regex(pattern)
      # Escape special regex characters first
      escaped = Regexp.escape(pattern)
      # Convert glob patterns to regex patterns
      escaped.gsub("\\*", '.*').gsub("\\?", '.')
    end

    def derive_lang_from_path(doc)
      unless @lang_from_path
        return nil
      end

      segments = split_on_multiple_delimiters(doc.path)
      # loop through all segments and return the first configured language
      segments.each do |segment|
        return segment if @languages.include?(segment)
      end

      # a segment of the project relative path that only differs from a
      # configured language by case is a mis-cased language code rather than
      # default language content. With unconfigured_lang set to error or ignore
      # it is reported as the (unconfigured) language of the document, while
      # generate keeps the behaviour of older releases and falls back to the
      # default language
      return nil if @unconfigured_lang == 'generate'

      split_on_multiple_delimiters(doc.relative_path.to_s).find do |segment|
        all_languages.any? { |lang| lang.casecmp?(segment) }
      end
    end

    # assigns natural permalinks to documents and prioritizes documents with
    # active_lang languages over others.  If lang is not set in front matter,
    # then this tries to derive from the path, if the lang_from_path is set.
    # otherwise it will assign the document to the default_lang
    def coordinate_documents(docs)
      regex = document_url_regex
      approved = {}
      # page_id => { lang => permalink } for every document that was read, the
      # ones this language build discards included.  Documents without an
      # explicit page_id are keyed by their language stripped url, so an
      # ordinary blog post can be matched with its translations as well.
      translations = {}

      docs.each do |doc|
        lang = doc.data['lang'] || derive_lang_from_path(doc)
        # unconfigured_lang decides what happens to a document whose language
        # (or mis-cased code) is not configured: fail the build, leave the
        # document out, or build it regardless (see unconfigured_lang_allowed?)
        next if lang && !unconfigured_lang_allowed?(doc, lang, doc.data['lang'] ? 'lang' : 'path segment')

        lang ||= @default_lang

        lang_exclusive = doc.data['lang-exclusive'] || []
        lang_exclusive.each { |exclusive_lang| unconfigured_lang_allowed?(doc, exclusive_lang, 'lang-exclusive') }

        url = doc.url.gsub(regex, '/')
        page_id = doc.data['page_id'] || url
        doc.data['permalink'] = url if doc.data['permalink'].to_s.empty? && !doc.data['lang'].to_s.empty?
        # Set rendered_lang to indicate what language this page is actually rendered in
        # This allows templates to detect fallback pages (rendered_lang != active_lang)
        doc.data['rendered_lang'] = lang

        # remember where this language version lives before the document is
        # filtered out of the build, so the surviving document still knows
        # which languages it has been translated into
        translations[page_id] ||= {}
        translations[page_id][lang] ||= doc.data['permalink'] || url

        # skip entirely if nothing to check
        next if @file_langs.nil?
        # skip this document if it has already been processed
        next if @file_langs[page_id] == @active_lang
        # skip this document if it has a fallback and it isn't assigned to the active language
        next if @file_langs[page_id] == @default_lang && lang != @active_lang
        # skip this document if it has lang-exclusive defined and the active_lang is not included
        next if !lang_exclusive.empty? && !lang_exclusive.include?(@active_lang)

        approved[page_id] = doc
        @file_langs[page_id] = lang
      end
      approved.each do |page_id, doc|
        assignPageRedirects(doc, docs)
        assignPageLanguagePermalinks(doc, docs)
        assignTranslatedPermalinks(doc, translations[page_id])
        assignCanonicalUrl(doc, translations[page_id])
      end
      approved.values
    end

    def assignPageRedirects(doc, docs)
      # Preserve and normalize user-defined redirect_from
      user_redirects = doc.data['redirect_from'] || []
      user_redirects = [user_redirects] unless user_redirects.is_a?(Array)

      # Determine document language
      doc_lang = doc.data['lang'] || derive_lang_from_path(doc) || @default_lang

      # Scope user-defined redirects to document's language if non-default,
      # under the language url segment, unless a path is already prefixed
      if doc_lang != @default_lang && !user_redirects.empty?
        user_redirects = user_redirects.map { |redirect_path| localize_permalink(redirect_path, doc_lang) }
      end

      # Compute page_id based redirects (cross-language)
      computed_redirects = []
      pageId = doc.data['page_id']
      if !pageId.nil? && !pageId.empty?
        docs_with_same_id = docs.select { |dd| dd.data['page_id'] == pageId }
        docs_with_same_id.each do |dd|
          if dd.data['permalink'] != doc.data['permalink']
            computed_redirects << dd.data['permalink']
          end
        end
      end

      # Merge user-defined and computed redirects, removing duplicates
      all_redirects = (user_redirects + computed_redirects).uniq
      doc.data['redirect_from'] = all_redirects unless all_redirects.empty?
    end

    def assignPageLanguagePermalinks(doc, docs)
      pageId = doc.data['page_id']
      if !pageId.nil? && !pageId.empty?
        unless doc.data['permalink_lang'] then doc.data['permalink_lang'] = {} end

        permalinkDocs = docs.select do |dd|
          dd.data['page_id'] == pageId
        end
        permalinkDocs.each do |dd|
          doclang = dd.data['lang'] || derive_lang_from_path(dd) || @default_lang
          # only configured languages have a permalink, unconfigured ones are
          # dealt with in coordinate_documents (see unconfigured_lang_allowed?)
          next unless all_languages.include?(doclang)

          doc.data['permalink_lang'][doclang] = dd.data['permalink']
        end
      end
    end

    # fills in the permalinks of the translations that assignPageLanguagePermalinks
    # cannot see.  It only looks at documents with an explicit page_id, while
    # most sites match a document to its translations by filename or path, so
    # without this an ordinary blog post looks untranslated to i18n_headers.
    def assignTranslatedPermalinks(doc, translated_permalinks)
      return if translated_permalinks.nil? || translated_permalinks.empty?

      permalink_lang = doc.data['permalink_lang'] || {}
      translated_permalinks.each do |lang, permalink|
        permalink_lang[lang] ||= permalink
      end
      doc.data['permalink_lang'] = permalink_lang
    end

    # the permalink a document canonicalises to in the language being built.
    # A document with a real translation canonicalises to that translation,
    # while a document rendered as a fallback canonicalises to the default
    # language version when fallback_canonical_to_default_lang is set, and to
    # itself otherwise.
    def canonical_permalink(doc, translated_permalinks)
      translated_permalinks ||= {}
      own_permalink = translated_permalinks[doc.data['rendered_lang']] ||
        doc.data['permalink'] || doc.url

      if @fallback_canonical_to_default_lang && !translated_permalinks.key?(@active_lang)
        localize_permalink(translated_permalinks[@default_lang] || own_permalink, @default_lang)
      else
        localize_permalink(translated_permalinks[@active_lang] || own_permalink, @active_lang)
      end
    end

    # prefixes a permalink with the url segment of its language, the default
    # language and already prefixed permalinks are left alone
    def localize_permalink(permalink, lang)
      permalink = "/#{permalink}" unless permalink.start_with?('/')
      return permalink if lang == @default_lang || lang_url_prefixes(lang).any? { |prefix| permalink.start_with?(prefix) }

      "/#{lang_url(lang)}#{permalink}"
    end

    # strips the url prefix of a language off a permalink, so /pt-br/about/
    # becomes /about/, permalinks without the prefix are left alone
    def delocalize_permalink(permalink, lang)
      permalink = "/#{permalink}" unless permalink.start_with?('/')
      prefix = lang_url_prefixes(lang).find { |p| permalink.start_with?(p) }
      prefix ? "/#{permalink.delete_prefix(prefix)}" : permalink
    end

    # publishes the canonical url of a document as page.canonical_url, so that
    # other plugins (jekyll-seo-tag, feeds, sitemaps) emit the same canonical
    # url as the i18n_headers tag does
    def assignCanonicalUrl(doc, translated_permalinks)
      doc.data['canonical_url'] = "#{config['url']}#{config['baseurl']}#{canonical_permalink(doc, translated_permalinks)}"
    end

    # performs any necessary operations on the documents before rendering them
    def process_documents(docs)
      # return if @active_lang == @default_lang

      url = config.fetch('url', false)
      rel_regex = relative_url_regex(false)
      abs_regex = absolute_url_regex(url, false)
      non_rel_regex = relative_url_regex(true)
      non_abs_regex = absolute_url_regex(url, true)
      docs.each do |doc|
        unless @active_lang == @default_lang then relativize_urls(doc, rel_regex) end
        correct_nonrelativized_urls(doc, non_rel_regex)
        if url
          unless @active_lang == @default_lang then relativize_absolute_urls(doc, abs_regex, url) end
          correct_nonrelativized_absolute_urls(doc, non_abs_regex, url)
        end
      end
    end

    # a regex that matches urls or permalinks with i18n prefixes or suffixes
    # matches /en/foo , .en/foo , foo.en/ and other simmilar default urls
    # made by jekyll when parsing documents without explicitly set permalinks
    def document_url_regex
      regex = ''
      lang_url_segments.each do |segment|
        regex += "([/.]#{Regexp.escape(segment)}[/.])|"
      end
      regex.chomp! '|'
      /#{regex}/
    end

    # a regex that matches relative urls in a html document
    # matches href="baseurl/foo/bar-baz" href="/foo/bar-baz" and others like it
    # avoids matching excluded files.  prepare makes sure
    # that all @exclude dirs have a trailing slash.
    def relative_url_regex(disabled = false)
      regex = ''
      unless disabled
        @exclude.each do |x|
          escaped_x = glob_to_regex(x)
          regex += "(?!#{escaped_x})"
        end
        lang_url_segments.each do |x|
          escaped_x = Regexp.escape(x)
          regex += "(?!#{escaped_x}/)"
        end
      end
      start = disabled ? 'ferh' : 'href'
      # canonical links are never relativized, polyglot decides what a document
      # canonicalises to and writes it out in full
      neglookbehind = disabled ? "" : "(?<!rel=\"canonical\" )"
      %r{#{neglookbehind}#{start}="?#{@baseurl}/((?:#{regex}[^,'"\s/?.]+\.?)*(?:/[^\]\[)("'\s]*)?)"}
    end

    # a regex that matches absolute urls in a html document
    # matches href="http://baseurl/foo/bar-baz" and others like it
    # avoids matching excluded files.  prepare makes sure
    # that all @exclude dirs have a trailing slash.
    def absolute_url_regex(url, disabled = false)
      regex = ''
      unless disabled
        @exclude.each do |x|
          escaped_x = glob_to_regex(x)
          regex += "(?!#{escaped_x})"
        end
        lang_url_segments.each do |x|
          escaped_x = Regexp.escape(x)
          regex += "(?!#{escaped_x}/)"
        end
      end
      start = disabled ? 'ferh' : 'href'
      # Build negative lookbehind to exclude hreflang and canonical URLs from
      # relativization.  hreflang tags for the default language and x-default
      # already point at the right url, and a canonical url is decided by
      # polyglot (see canonical_permalink) rather than by the language of the
      # page it appears on.
      neglookbehind = disabled ? "" : "(?<!hreflang=\"#{@default_lang}\" |hreflang=\"x-default\" |rel=\"canonical\" )"
      %r{#{neglookbehind}#{start}="?#{url}#{@baseurl}/((?:#{regex}[^,'"\s/?.]+\.?)*(?:/[^\]\[)("'\s]*)?)"}
    end

    def relativize_urls(doc, regex)
      return if doc.output.nil?

      modified_output = doc.output.dup
      modified_output.gsub!(regex, "href=\"#{@baseurl}/#{lang_url(@active_lang)}/\\1\"")
      doc.output = modified_output
    end

    def relativize_absolute_urls(doc, regex, url)
      return if doc.output.nil?

      modified_output = doc.output.dup
      modified_output.gsub!(regex, "href=\"#{url}#{@baseurl}/#{lang_url(@active_lang)}/\\1\"")
      doc.output = modified_output
    end

    def correct_nonrelativized_absolute_urls(doc, regex, url)
      return if doc.output.nil?

      modified_output = doc.output.dup
      modified_output.gsub!(regex, "href=\"#{url}#{@baseurl}/\\1\"")
      doc.output = modified_output
    end

    def correct_nonrelativized_urls(doc, regex)
      return if doc.output.nil?

      modified_output = doc.output.dup
      modified_output.gsub!(regex, "href=\"#{@baseurl}/\\1\"")
      doc.output = modified_output
    end
  end
end
