require 'English'
require 'etc'

include Process
module Jekyll
  class Site
    attr_reader :default_lang, :languages, :exclude_from_localization, :lang_vars, :lang_from_path, :fallback_canonical_to_default_lang, :lang_norm_map, :languages_normalized, :serial_default_lang, :generate_fallback_pages
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
      # When false, a language pass only approves documents whose own lang
      # matches that pass - no default-language body is generated under a
      # localised URL for translations that don't exist. See README.
      @generate_fallback_pages = config.fetch('generate_fallback_pages', true)
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

      # Create normalized lookup hash: lowercase -> original case
      # Include default_lang so it's always recognized even if not in languages array
      @lang_norm_map = {}
      @lang_norm_map[@default_lang.downcase] = @default_lang
      @languages.each { |lang| @lang_norm_map[lang.downcase] = lang }

      # Store normalized versions for fast lookup
      @languages_normalized = @languages.map(&:downcase)

      @keep_files += (@languages - [@default_lang])
      @active_lang = @default_lang
      @lang_vars = config.fetch('lang_vars', [])
    end

    # Normalizes a language code to its canonical form from config
    # Returns the original case from config, or nil if not found
    def normalize_lang(lang_code)
      return nil if lang_code.nil? || lang_code.empty?
      @lang_norm_map[lang_code.downcase]
    end

    # Case-insensitive check if language exists in config
    def lang_exists?(lang_code)
      return false if lang_code.nil? || lang_code.empty?
      @languages_normalized.include?(lang_code.downcase)
    end

    alias process_orig process
    def process
      prepare
      all_langs = ([@default_lang] + @languages).uniq
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
      lang_vars.each do |v|
        payload['site'][v] = active_lang
      end
      payload
    end

    def process_language(lang)
      @active_lang = lang
      config['active_lang'] = @active_lang
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
      @dest = "#{@dest}/#{@active_lang}"
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
      # loop through all segments and check if they match the language regex
      segments.each do |segment|
        # Use case-insensitive matching and return config case
        normalized = normalize_lang(segment)
        return normalized if normalized
      end

      nil
    end

    # assigns natural permalinks to documents and prioritizes documents with
    # active_lang languages over others.  If lang is not set in front matter,
    # then this tries to derive from the path, if the lang_from_path is set.
    # otherwise it will assign the document to the default_lang
    def coordinate_documents(docs)
      regex = document_url_regex
      approved = {}
      # Build set of valid languages (default + configured)
      valid_languages = ([@default_lang] + @languages).uniq

      docs.each do |doc|
        # Normalize language codes for comparison
        doc_lang_raw = doc.data['lang'] || derive_lang_from_path(doc)
        lang = normalize_lang(doc_lang_raw) || @default_lang

        # FILTER: Skip documents whose explicit lang is not in configured languages.
        # Check the raw value so that documents with an unconfigured lang like 'de'
        # are excluded even though normalize_lang maps them to nil -> default_lang.
        if doc_lang_raw && !normalize_lang(doc_lang_raw)
          Jekyll.logger.warn "Polyglot:", "Skipping #{doc.relative_path} - lang '#{doc_lang_raw}' not in configured languages #{valid_languages.inspect}"
          next
        end

        # Update the document's lang data to use canonical case
        # This ensures downstream code always works with consistent casing
        if doc_lang_raw && lang != doc_lang_raw
          doc.data['lang'] = lang
        end

        lang_exclusive = doc.data['lang-exclusive'] || []
        # Normalize lang-exclusive entries
        lang_exclusive_normalized = lang_exclusive.map { |l| normalize_lang(l) }.compact

        url = doc.url.gsub(regex, '/')
        page_id = doc.data['page_id'] || url
        doc.data['permalink'] = url if doc.data['permalink'].to_s.empty? && !doc.data['lang'].to_s.empty?
        # Set rendered_lang to indicate what language this page is actually rendered in
        # This allows templates to detect fallback pages (rendered_lang != active_lang)
        doc.data['rendered_lang'] = lang

        # skip entirely if nothing to check
        next if @file_langs.nil?
        # skip this document if fallback pages are disabled and it isn't in the active language
        next if !@generate_fallback_pages && lang != @active_lang
        # skip this document if it has already been processed
        next if @file_langs[page_id] == @active_lang
        # skip this document if it has a fallback and it isn't assigned to the active language
        next if @file_langs[page_id] == @default_lang && lang != @active_lang
        # skip this document if it has lang-exclusive defined and the active_lang is not included
        next if !lang_exclusive_normalized.empty? && !lang_exclusive_normalized.include?(@active_lang)

        approved[page_id] = doc
        @file_langs[page_id] = lang
      end
      approved.each_value do |doc|
        assignPageRedirects(doc, docs)
        assignPageLanguagePermalinks(doc, docs)
      end
      approved.values
    end

    def assignPageRedirects(doc, docs)
      # Preserve and normalize user-defined redirect_from
      user_redirects = doc.data['redirect_from'] || []
      user_redirects = [user_redirects] unless user_redirects.is_a?(Array)

      # Determine document language
      doc_lang = doc.data['lang'] || derive_lang_from_path(doc) || @default_lang

      # Scope user-defined redirects to document's language if non-default
      if doc_lang != @default_lang && !user_redirects.empty?
        user_redirects = user_redirects.map do |redirect_path|
          # Normalize path to start with /
          redirect_path = "/#{redirect_path}" unless redirect_path.start_with?('/')
          # Only prefix if not already prefixed with this language
          if redirect_path.start_with?("/#{doc_lang}/")
            redirect_path
          else
            "/#{doc_lang}#{redirect_path}"
          end
        end
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

        # Build set of valid languages
        valid_languages = ([@default_lang] + @languages).uniq

        permalinkDocs = docs.select do |dd|
          dd.data['page_id'] == pageId
        end
        permalinkDocs.each do |dd|
          # Normalize the language code
          doclang_raw = dd.data['lang'] || derive_lang_from_path(dd)
          doclang = normalize_lang(doclang_raw) || @default_lang

          # FILTER: Only include permalinks for configured languages.
          # Check raw value so unconfigured languages are excluded.
          next if doclang_raw && !normalize_lang(doclang_raw)

          doc.data['permalink_lang'][doclang] = dd.data['permalink']
        end
      end
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
      (@languages || []).each do |lang|
        regex += "([/.]#{lang}[/.])|"
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
        @languages.each do |x|
          escaped_x = Regexp.escape(x)
          regex += "(?!#{escaped_x}/)"
        end
      end
      start = disabled ? 'ferh' : 'href'
      %r{#{start}="?#{@baseurl}/((?:#{regex}[^,'"\s/?.]+\.?)*(?:/[^\]\[)("'\s]*)?)"}
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
        @languages.each do |x|
          escaped_x = Regexp.escape(x)
          regex += "(?!#{escaped_x}/)"
        end
      end
      start = disabled ? 'ferh' : 'href'
      # Build negative lookbehind to exclude hreflang URLs from relativization
      # hreflang tags for default language and x-default should not be relativized
      neglookbehind = disabled ? "" : "(?<!hreflang=\"#{@default_lang}\" |hreflang=\"x-default\" )"
      %r{#{neglookbehind}#{start}="?#{url}#{@baseurl}/((?:#{regex}[^,'"\s/?.]+\.?)*(?:/[^\]\[)("'\s]*)?)"}
    end

    def relativize_urls(doc, regex)
      return if doc.output.nil?

      modified_output = doc.output.dup
      modified_output.gsub!(regex, "href=\"#{@baseurl}/#{@active_lang}/\\1\"")
      doc.output = modified_output
    end

    def relativize_absolute_urls(doc, regex, url)
      return if doc.output.nil?

      modified_output = doc.output.dup
      modified_output.gsub!(regex, "href=\"#{url}#{@baseurl}/#{@active_lang}/\\1\"")
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
