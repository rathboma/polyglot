require 'rspec/helper'
require 'fileutils'
require 'tmpdir'

# End-to-end specs for the `lang_urls` option. They build a real site with
#
#   languages: [en, es, pt-BR]
#   lang_urls:
#     pt-BR: pt-br
#
# and assert on what lands in _site: the pt-BR language is served under
# /pt-br/ everywhere polyglot writes a url, while the language code itself
# (site.active_lang, hreflang attributes, front matter, file paths) stays pt-BR.
describe 'lang_urls' do
  def build_site(config_overrides = {})
    config = {
      'source' => @src,
      'destination' => @dest,
      'url' => 'https://example.com',
      'baseurl' => '',
      'languages' => ['en', 'es', 'pt-BR'],
      'default_lang' => 'en',
      'lang_urls' => { 'pt-BR' => 'pt-br' },
      'parallel_localization' => false
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
      <meta name="redirect-from" content="{{ page.redirect_from | join: ',' }}">
      </head>
      <body>
      {{ content }}
      <a href="/about/">relative</a>
      <a href="https://example.com/about/">absolute</a>
      <nav>{% for lang in site.languages %}<a {% static_href %}href="{% if lang == site.default_lang %}/{% else %}/{{ site.lang_urls[lang] }}/{% endif %}"{% endstatic_href %}>{{ lang }}</a>{% endfor %}</nav>
      </body>
      </html>
    LAYOUT
  end

  def write_content
    write_file('about.md', <<~PAGE)
      ---
      layout: default
      title: About
      lang: en
      permalink: /about/
      page_id: about
      ---
      About us, in English.
    PAGE
    write_file('sobre.md', <<~PAGE)
      ---
      layout: default
      title: Sobre
      lang: pt-BR
      permalink: /sobre/
      page_id: about
      redirect_from: /antigo/
      ---
      Sobre nos, em portugues.
    PAGE
    write_file('_posts/2024-01-01-english-only.md', <<~POST)
      ---
      layout: default
      title: English Only
      ---
      Only written in English.
    POST
    write_file('_redirects', "/github https://github.com/org/repo 302\n")
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
    write_content
  end

  after do
    Jekyll.logger.log_level = @log_level
    FileUtils.rm_rf(@tmpdir)
  end

  describe 'the built site' do
    before do
      @site = build_site
    end

    it 'writes the pt-BR site into the pt-br directory' do
      expect(File.exist?(File.join(@dest, 'pt-br/sobre/index.html'))).to be true
      expect(File.exist?(File.join(@dest, 'pt-br/2024/01/01/english-only.html'))).to be true
      expect(File.exist?(File.join(@dest, 'es/about/index.html'))).to be true
      expect(Dir.exist?(File.join(@dest, 'pt-BR'))).to be false
    end

    it 'keeps pt-BR as the active language of the pt-br site' do
      expect(output_for('pt-br/sobre/index.html')).to include('<html lang="pt-BR">')
      expect(output_for('pt-br/2024/01/01/english-only.html')).to include('<html lang="pt-BR">')
      expect(@site.languages).to eq(['en', 'es', 'pt-BR'])
    end

    it 'relativizes links on the pt-br site into /pt-br/' do
      html = output_for('pt-br/sobre/index.html')
      expect(html).to include('<a href="/pt-br/about/">relative</a>')
      expect(html).to include('<a href="https://example.com/pt-br/about/">absolute</a>')
      expect(html).not_to include('/pt-BR/')
    end

    it 'relativizes links on fallback pages of the pt-br site into /pt-br/' do
      html = output_for('pt-br/2024/01/01/english-only.html')
      expect(html).to include('<a href="/pt-br/about/">relative</a>')
      expect(html).to include('<a href="https://example.com/pt-br/about/">absolute</a>')
    end

    it 'leaves languages without a lang_urls entry alone' do
      html = output_for('es/about/index.html')
      expect(html).to include('<html lang="es">')
      expect(html).to include('<a href="/es/about/">relative</a>')
      expect(canonical_in('es/about/index.html')).to eq('https://example.com/es/about/')
    end

    it 'canonicalizes the pt-BR translation to its /pt-br/ url' do
      expect(canonical_in('pt-br/sobre/index.html')).to eq('https://example.com/pt-br/sobre/')
      expect(canonical_url_attribute_in('pt-br/sobre/index.html')).to eq('https://example.com/pt-br/sobre/')
    end

    it 'canonicalizes a fallback page of the pt-br site to its /pt-br/ url' do
      expect(canonical_in('pt-br/2024/01/01/english-only.html')).to eq('https://example.com/pt-br/2024/01/01/english-only.html')
      expect(canonical_url_attribute_in('pt-br/2024/01/01/english-only.html')).to eq('https://example.com/pt-br/2024/01/01/english-only.html')
    end

    it 'advertises the pt-BR translation under its language code and its /pt-br/ url' do
      expect(hreflangs_in('about/index.html')['pt-BR']).to eq('https://example.com/pt-br/sobre/')
      expect(hreflangs_in('about/index.html')).not_to have_key('pt-br')
      expect(hreflangs_in('pt-br/sobre/index.html')['pt-BR']).to eq('https://example.com/pt-br/sobre/')
      expect(hreflangs_in('pt-br/sobre/index.html')['en']).to eq('https://example.com/about/')
      expect(hreflangs_in('pt-br/sobre/index.html')['x-default']).to eq('https://example.com/about/')
      expect(hreflangs_in('es/about/index.html')['pt-BR']).to eq('https://example.com/pt-br/sobre/')
    end

    it 'scopes redirect_from paths of pt-BR documents to /pt-br/' do
      expect(output_for('pt-br/sobre/index.html')).to include('<meta name="redirect-from" content="/pt-br/antigo/,/about/">')
    end

    it 'exposes the url segment of every language to templates as site.lang_urls' do
      html = output_for('about/index.html')
      expect(html).to include('<a href="/">en</a>')
      expect(html).to include('<a href="/es/">es</a>')
      expect(html).to include('<a href="/pt-br/">pt-BR</a>')
      expect(@site.site_payload['site']['lang_urls']).to eq('en' => 'en', 'es' => 'es', 'pt-BR' => 'pt-br')
    end

    it 'keeps the pt-br directory when the site is rebuilt' do
      silence_stdout { @site.process }
      expect(File.exist?(File.join(@dest, 'pt-br/sobre/index.html'))).to be true
      expect(File.exist?(File.join(@dest, 'es/about/index.html'))).to be true
    end
  end

  describe 'with fallback_canonical_to_default_lang' do
    before do
      build_site('fallback_canonical_to_default_lang' => true)
    end

    it 'canonicalizes a fallback page of the pt-br site to the default language url' do
      expect(canonical_in('pt-br/2024/01/01/english-only.html')).to eq('https://example.com/2024/01/01/english-only.html')
      expect(canonical_url_attribute_in('pt-br/2024/01/01/english-only.html')).to eq('https://example.com/2024/01/01/english-only.html')
    end

    it 'still canonicalizes the pt-BR translation to its /pt-br/ url' do
      expect(canonical_in('pt-br/sobre/index.html')).to eq('https://example.com/pt-br/sobre/')
    end
  end

  describe 'with localize_redirects' do
    before do
      build_site('localize_redirects' => true)
    end

    it 'localizes the Netlify _redirects file with /pt-br/' do
      redirects = File.read(File.join(@dest, '_redirects'))
      expect(redirects).to include("/github https://github.com/org/repo 302\n")
      expect(redirects).to include("/es/github https://github.com/org/repo 302\n")
      expect(redirects).to include("/pt-br/github https://github.com/org/repo 302\n")
      expect(redirects).not_to include('/pt-BR/')
    end
  end

  describe 'with lang_from_path' do
    before do
      write_file('_posts/pt-BR/2024-02-01-caminho.md', <<~POST)
        ---
        layout: default
        title: Caminho
        ---
        Escrito em portugues.
      POST
      build_site('lang_from_path' => true)
    end

    it 'identifies the language by its code in the path and serves it under /pt-br/' do
      expect(File.exist?(File.join(@dest, 'pt-br/2024/02/01/caminho.html'))).to be true
      expect(output_for('pt-br/2024/02/01/caminho.html')).to include('Escrito em portugues.')
      expect(output_for('pt-br/2024/02/01/caminho.html')).to include('<html lang="pt-BR">')
      expect(canonical_in('pt-br/2024/02/01/caminho.html')).to eq('https://example.com/pt-br/2024/02/01/caminho.html')
    end
  end

  describe 'without lang_urls' do
    before do
      build_site('lang_urls' => nil)
    end

    it 'keeps serving pt-BR under its language code' do
      expect(File.exist?(File.join(@dest, 'pt-BR/sobre/index.html'))).to be true
      expect(Dir.exist?(File.join(@dest, 'pt-br'))).to be false
      expect(canonical_in('pt-BR/sobre/index.html')).to eq('https://example.com/pt-BR/sobre/')
      expect(output_for('pt-BR/sobre/index.html')).to include('<a href="/pt-BR/about/">relative</a>')
      expect(output_for('about/index.html')).to include('<a href="/pt-BR/">pt-BR</a>')
    end
  end
end
