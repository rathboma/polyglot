require 'rspec/helper'
require 'fileutils'
require 'tmpdir'

# Regression specs for canonical URL handling of untranslated (fallback) content.
#
# The README promises that with `fallback_canonical_to_default_lang: true` a page
# without a translation renders in the fallback language but points its canonical
# URL at the default language version. These specs build a real site and assert on
# the HTML that actually lands in _site, because the bug is only visible there:
# `{% i18n_headers %}` emits the correct canonical, and the `:site, :post_render`
# hook (Site#process_documents -> #relativize_absolute_urls) then rewrites it into
# the active language, so every fallback page ends up canonicalised to itself.
describe 'canonical urls for fallback content' do
  def build_site(config_overrides = {})
    config = {
      'source' => @src,
      'destination' => @dest,
      'url' => 'https://example.com',
      'baseurl' => '',
      'languages' => ['en', 'es', 'de'],
      'default_lang' => 'en',
      'parallel_localization' => false,
      'fallback_canonical_to_default_lang' => true
    }.merge(config_overrides)

    site = Site.new(Jekyll.configuration(config))
    silence_stdout { site.process }
    site
  end

  def write_file(relative_path, content)
    path = File.join(@src, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def write_layout
    write_file('_layouts/default.html', <<~LAYOUT)
      <!DOCTYPE html>
      <html lang="{{ site.active_lang }}">
      <head>
      {% i18n_headers %}
      <meta name="canonical-url-attribute" content="{{ page.canonical_url }}">
      </head>
      <body>{{ content }}</body>
      </html>
    LAYOUT
  end

  def output_for(relative_path)
    path = File.join(@dest, relative_path)
    raise "expected #{relative_path} to be written, found: #{Dir.glob(File.join(@dest, '**', '*.html')).inspect}" unless File.exist?(path)

    File.read(path)
  end

  def canonical_in(relative_path)
    output_for(relative_path)[/<link rel="canonical" href="([^"]+)"/, 1]
  end

  def canonical_url_attribute_in(relative_path)
    output_for(relative_path)[/<meta name="canonical-url-attribute" content="([^"]*)">/, 1]
  end

  def hreflangs_in(relative_path)
    output_for(relative_path).scan(/<link rel="alternate" hreflang="([^"]+)" href="([^"]+)"/).to_h
  end

  before do
    @log_level = Jekyll.logger.level
    Jekyll.logger.log_level = :error
    @tmpdir = Dir.mktmpdir
    @src = File.join(@tmpdir, 'site')
    @dest = File.join(@tmpdir, '_site')
    FileUtils.mkdir_p(@src)
    write_layout
  end

  after do
    Jekyll.logger.log_level = @log_level
    FileUtils.rm_rf(@tmpdir)
  end

  describe 'collection documents without an explicit permalink' do
    before do
      # A plain blog post: no lang, no permalink, no page_id - the shape of every
      # normal post in a real blog. It exists only in the default language.
      write_file('_posts/2024-01-01-untranslated-post.md', <<~POST)
        ---
        layout: default
        title: Untranslated Post
        ---
        Only written in English.
      POST
      build_site
    end

    it 'renders the fallback post into every language' do
      expect(File.exist?(File.join(@dest, '2024/01/01/untranslated-post.html'))).to be true
      expect(File.exist?(File.join(@dest, 'es/2024/01/01/untranslated-post.html'))).to be true
      expect(File.exist?(File.join(@dest, 'de/2024/01/01/untranslated-post.html'))).to be true
    end

    it 'canonicalises the default language build to itself' do
      expect(canonical_in('2024/01/01/untranslated-post.html'))
        .to eq('https://example.com/2024/01/01/untranslated-post.html')
    end

    it 'canonicalises the untranslated post to the default language url in every fallback language' do
      expect(canonical_in('es/2024/01/01/untranslated-post.html'))
        .to eq('https://example.com/2024/01/01/untranslated-post.html')
      expect(canonical_in('de/2024/01/01/untranslated-post.html'))
        .to eq('https://example.com/2024/01/01/untranslated-post.html')
    end

    it 'does not canonicalise a fallback post to itself' do
      expect(canonical_in('de/2024/01/01/untranslated-post.html'))
        .to_not eq('https://example.com/de/2024/01/01/untranslated-post.html')
    end

    it 'still advertises only the default language in hreflang tags' do
      expect(hreflangs_in('de/2024/01/01/untranslated-post.html').keys).to contain_exactly('en', 'x-default')
    end
  end

  describe 'collection documents with an explicit permalink and page_id' do
    before do
      # Even the fully annotated shape - explicit lang, permalink and page_id -
      # is canonicalised to itself once the page is rendered as a fallback.
      write_file('_posts/2024-02-01-annotated.md', <<~POST)
        ---
        layout: default
        title: Annotated Post
        lang: en
        page_id: annotated
        permalink: /blog/annotated/
        ---
        Only written in English.
      POST
      build_site
    end

    it 'canonicalises the fallback build to the default language url' do
      expect(canonical_in('de/blog/annotated/index.html')).to eq('https://example.com/blog/annotated/')
    end
  end

  describe 'custom collections without a translation' do
    before do
      write_file('_docs/getting-started.md', <<~DOC)
        ---
        layout: default
        title: Getting Started
        ---
        Only written in English.
      DOC
      build_site('collections' => {'docs' => {'output' => true}})
    end

    it 'canonicalises an untranslated collection document to the default language url' do
      expect(canonical_in('de/docs/getting-started.html')).to eq('https://example.com/docs/getting-started.html')
    end
  end

  describe 'pages without a translation' do
    before do
      write_file('about.md', <<~PAGE)
        ---
        layout: default
        title: About
        lang: en
        permalink: /about/
        ---
        About us, English only.
      PAGE
      build_site
    end

    it 'canonicalises an untranslated page to the default language url' do
      expect(canonical_in('de/about/index.html')).to eq('https://example.com/about/')
      expect(canonical_in('es/about/index.html')).to eq('https://example.com/about/')
    end
  end

  describe 'documents that do have a translation' do
    before do
      write_file('_posts/2024-03-01-translated.md', <<~POST)
        ---
        layout: default
        title: Translated Post
        lang: en
        page_id: translated
        permalink: /blog/translated/
        ---
        English version.
      POST
      write_file('_posts/2024-03-01-translated.es.md', <<~POST)
        ---
        layout: default
        title: Entrada Traducida
        lang: es
        page_id: translated
        permalink: /blog/traducida/
        ---
        Version espanola.
      POST
      build_site
    end

    it 'keeps the active language canonical for a real translation' do
      expect(canonical_in('es/blog/traducida/index.html')).to eq('https://example.com/es/blog/traducida/')
    end

    it 'canonicalises the default language build to itself' do
      expect(canonical_in('blog/translated/index.html')).to eq('https://example.com/blog/translated/')
    end

    it 'canonicalises a language with no translation to the default language url' do
      expect(canonical_in('de/blog/translated/index.html')).to eq('https://example.com/blog/translated/')
    end
  end

  describe 'canonical_url page attribute' do
    before do
      write_file('_posts/2024-04-01-untranslated-post.md', <<~POST)
        ---
        layout: default
        title: Untranslated Post
        ---
        Only written in English.
      POST
      build_site
    end

    # Other plugins (jekyll-seo-tag, sitemap generators, feed generators) read the
    # canonical URL from page data; polyglot currently exposes it nowhere, so the
    # only way to get a correct canonical is the i18n_headers tag.
    it 'publishes canonical_url on the default language build' do
      expect(canonical_url_attribute_in('2024/04/01/untranslated-post.html'))
        .to eq('https://example.com/2024/04/01/untranslated-post.html')
    end

    it 'publishes canonical_url on a fallback build pointing at the default language' do
      expect(canonical_url_attribute_in('de/2024/04/01/untranslated-post.html'))
        .to eq('https://example.com/2024/04/01/untranslated-post.html')
    end

    it 'publishes a canonical_url that matches the rendered canonical link' do
      %w[2024/04/01/untranslated-post.html es/2024/04/01/untranslated-post.html de/2024/04/01/untranslated-post.html].each do |path|
        expect(canonical_url_attribute_in(path)).to eq(canonical_in(path))
      end
    end
  end

  describe 'translations discovered through lang_from_path' do
    before do
      # Neither file carries `lang` in its front matter, so coordinate_documents
      # never assigns a permalink and i18n_headers cannot pair the two documents.
      write_file('_posts/2024-05-01-path-post.md', <<~POST)
        ---
        layout: default
        title: Path Post
        ---
        English version.
      POST
      write_file('_posts/es/2024-05-01-path-post.md', <<~POST)
        ---
        layout: default
        title: Entrada de Ruta
        ---
        Version espanola.
      POST
      build_site('lang_from_path' => true)
    end

    it 'renders the spanish translation for the spanish build' do
      expect(output_for('es/2024/05/01/path-post.html')).to include('Version espanola.')
    end

    it 'advertises the spanish translation in hreflang tags' do
      expect(hreflangs_in('2024/05/01/path-post.html').keys).to include('es')
    end

    it 'does not treat a real translation as a fallback page' do
      # The spanish build already emits the right canonical, but only by accident:
      # i18n_headers cannot see the translation, emits the default language
      # canonical as if this were a fallback page, and relativize_absolute_urls
      # then rewrites it back into /es/. The missing hreflang tag is what gives
      # the mis-detection away.
      expect(canonical_in('es/2024/05/01/path-post.html')).to eq('https://example.com/es/2024/05/01/path-post.html')
      expect(hreflangs_in('es/2024/05/01/path-post.html').keys).to include('es')
    end
  end

  describe 'root cause: post-render url relativization rewrites the canonical link' do
    it 'leaves the canonical link of a fallback document alone' do
      site = Site.new(
        Jekyll.configuration(
          'source'                             => @src,
          'destination'                        => @dest,
          'url'                                => 'https://example.com',
          'languages'                          => ['en', 'es', 'de'],
          'default_lang'                       => 'en',
          'fallback_canonical_to_default_lang' => true
        )
      )
      site.prepare
      site.active_lang = 'de'

      collection = Jekyll::Collection.new(site, 'posts')
      doc = Jekyll::Document.new('2024-01-01-untranslated-post.md', site: site, collection: collection)
      doc.data['lang'] = 'en'
      doc.data['rendered_lang'] = 'en'
      doc.output = <<~HTML
        <link rel="canonical" href="https://example.com/2024/01/01/untranslated-post.html"/>
        <a href="https://example.com/2024/01/01/untranslated-post.html">self</a>
      HTML

      site.process_documents([doc])

      expect(doc.output).to include('<link rel="canonical" href="https://example.com/2024/01/01/untranslated-post.html"/>')
      # other links on a fallback page are still relativized into the active language
      expect(doc.output).to include('<a href="https://example.com/de/2024/01/01/untranslated-post.html">self</a>')
    end
  end
end
