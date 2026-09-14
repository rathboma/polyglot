require 'rspec/helper'
require 'nokogiri'
require 'fileutils'
require 'tmpdir'

# Polyglot builds one copy of the site per language.  When a page has no
# translation for the language being built, the document from another language
# is rendered in its place - a "fallback page".  The body of that page is in
# the language it was written in, but everything that keys off site.active_lang
# (the lang_vars and the localized site.data) renders in the language the site
# is being built for, so the page ends up half in one language and half in the
# other: /es/contact/ declares lang="en" while its navigation, buttons and
# strings are all spanish.
#
# `full_default_lang_fallback` resolves that by pointing those variables at
# page.rendered_lang, making a fallback page a complete copy of the page in the
# language its content is actually written in.
describe 'fallback page language' do
  let(:tmpdir) { Dir.mktmpdir }
  let(:source_dir) { File.join(tmpdir, 'src') }
  let(:dest_dir) { File.join(tmpdir, '_site') }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def layout
    <<~HTML
      ---
      ---
      <html lang="{{ page.rendered_lang }}">
      <head>{% I18n_Headers %}</head>
      <body>
      <span id="active-lang">{{ site.active_lang }}</span>
      <span id="lang-var">{{ site.langstr }}</span>
      <span id="build-lang">{{ site.build_lang }}</span>
      <span id="merged-data">{{ site.data.strings.hello }}</span>
      <span id="keyed-data">{{ site.data[site.active_lang].strings.hello }}</span>
      <span id="lang-var-data">{{ site.data[site.langstr].strings.hello }}</span>
      <span id="rendered-lang">{{ page.rendered_lang }}</span>
      <div id="body">{{ content }}</div>
      </body>
      </html>
    HTML
  end

  def write_file(relative_path, content)
    path = File.join(source_dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def write_page(name, lang, permalink, page_id, body)
    write_file(name, <<~PAGE)
      ---
      layout: default
      lang: #{lang}
      permalink: #{permalink}
      page_id: #{page_id}
      ---
      #{body}
    PAGE
  end

  def write_site
    write_file('_data/en/strings.yml', "hello: Hello\n")
    write_file('_data/es/strings.yml', "hello: Hola\n")
    write_file('_layouts/default.html', layout)
    # about is translated into both languages
    write_page('en.about.md', 'en', '/about/', 'about', 'About us')
    write_page('es.about.md', 'es', '/sobre/', 'about', 'Sobre nosotros')
    # contact is only written in english, so the spanish site falls back to it
    write_page('en.contact.md', 'en', '/contact/', 'contact', 'Contact us')
    # samba is only written in spanish, so the english site falls back to it
    write_page('es.samba.md', 'es', '/samba/', 'samba', 'Samba')
  end

  def build_site(config_overrides = {})
    write_site
    site = Site.new(
      Jekyll.configuration({
        'source' => source_dir,
        'destination' => dest_dir,
        'languages' => ['en', 'es'],
        'default_lang' => 'en',
        'lang_vars' => ['langstr'],
        'parallel_localization' => false,
        'url' => 'https://example.com'
      }.merge(config_overrides))
    )
    silence_stdout { site.process }
    site
  end

  def page_at(relative_path)
    path = File.join(dest_dir, relative_path)
    raise "expected #{relative_path} to be built" unless File.exist?(path)

    Nokogiri::HTML(File.read(path))
  end

  def value_of(page, id)
    page.at_css("##{id}")&.text&.strip
  end

  def canonical_of(page)
    page.at_css('link[rel="canonical"]')['href']
  end

  def hreflangs_of(page)
    page.css('link[rel="alternate"]').to_h { |link| [link['hreflang'], link['href']] }
  end

  describe 'by default' do
    before do
      build_site
    end

    it 'exposes the language the site is being built for as site.build_lang' do
      expect(value_of(page_at('about/index.html'), 'build-lang')).to eq('en')
      expect(value_of(page_at('es/sobre/index.html'), 'build-lang')).to eq('es')
      expect(value_of(page_at('es/contact/index.html'), 'build-lang')).to eq('es')
    end

    it 'renders a fallback page as a hybrid of both languages' do
      fallback = page_at('es/contact/index.html')

      # the body is english, and the page honestly reports that it is
      expect(value_of(fallback, 'body')).to include('Contact us')
      expect(value_of(fallback, 'rendered-lang')).to eq('en')

      # ...but every language dependent site variable is still spanish
      expect(value_of(fallback, 'active-lang')).to eq('es')
      expect(value_of(fallback, 'lang-var')).to eq('es')
      expect(value_of(fallback, 'merged-data')).to eq('Hola')
      expect(value_of(fallback, 'keyed-data')).to eq('Hola')
    end

    it 'renders translated pages entirely in the language being built' do
      translated = page_at('es/sobre/index.html')

      expect(value_of(translated, 'body')).to include('Sobre nosotros')
      expect(value_of(translated, 'rendered-lang')).to eq('es')
      expect(value_of(translated, 'active-lang')).to eq('es')
      expect(value_of(translated, 'merged-data')).to eq('Hola')
    end
  end

  describe 'with full_default_lang_fallback enabled' do
    before do
      build_site('full_default_lang_fallback' => true)
    end

    it 'renders a fallback page as a full copy of the page in its own language' do
      fallback = page_at('es/contact/index.html')

      expect(value_of(fallback, 'body')).to include('Contact us')
      expect(value_of(fallback, 'rendered-lang')).to eq('en')
      expect(value_of(fallback, 'active-lang')).to eq('en')
      expect(value_of(fallback, 'lang-var')).to eq('en')
      expect(value_of(fallback, 'merged-data')).to eq('Hello')
      expect(value_of(fallback, 'keyed-data')).to eq('Hello')
      expect(value_of(fallback, 'lang-var-data')).to eq('Hello')
    end

    it 'still reports the language being built as site.build_lang' do
      expect(value_of(page_at('es/contact/index.html'), 'build-lang')).to eq('es')
      expect(value_of(page_at('es/sobre/index.html'), 'build-lang')).to eq('es')
    end

    it 'leaves translated pages in the language being built' do
      translated = page_at('es/sobre/index.html')

      expect(value_of(translated, 'body')).to include('Sobre nosotros')
      expect(value_of(translated, 'active-lang')).to eq('es')
      expect(value_of(translated, 'lang-var')).to eq('es')
      expect(value_of(translated, 'merged-data')).to eq('Hola')
      expect(value_of(translated, 'keyed-data')).to eq('Hola')
    end

    it 'does not leak the fallback language into pages rendered after it' do
      # samba renders after the contact fallback page in the spanish build
      samba = page_at('es/samba/index.html')

      expect(value_of(samba, 'active-lang')).to eq('es')
      expect(value_of(samba, 'lang-var')).to eq('es')
      expect(value_of(samba, 'merged-data')).to eq('Hola')
    end

    it 'follows the rendered language when the default language site falls back' do
      # samba is only written in spanish, so the english site serves it as a
      # fallback and it should be a full spanish copy
      fallback = page_at('samba/index.html')

      expect(value_of(fallback, 'body')).to include('Samba')
      expect(value_of(fallback, 'rendered-lang')).to eq('es')
      expect(value_of(fallback, 'active-lang')).to eq('es')
      expect(value_of(fallback, 'lang-var')).to eq('es')
      expect(value_of(fallback, 'merged-data')).to eq('Hola')
    end

    it 'leaves the default language site alone for its own pages' do
      about = page_at('about/index.html')

      expect(value_of(about, 'body')).to include('About us')
      expect(value_of(about, 'active-lang')).to eq('en')
      expect(value_of(about, 'merged-data')).to eq('Hello')
    end

    it 'leaves the canonical and hreflang urls of a fallback page alone' do
      # a fallback page is still published under /es/, so I18n_Headers keeps
      # describing it from the language being built.  This option only changes
      # the language a page is rendered in, never where it is published.
      fallback = page_at('es/contact/index.html')

      expect(canonical_of(fallback)).to eq('https://example.com/es/contact/')
      expect(hreflangs_of(fallback)).to eq(
        'en' => 'https://example.com/contact/',
        'x-default' => 'https://example.com/contact/'
      )
    end
  end

  describe Site do
    def prepared_site(config_overrides = {})
      site = Site.new(
        Jekyll.configuration({
          'source' => File.expand_path('../../fixture', __dir__),
          'languages' => ['en', 'es'],
          'default_lang' => 'en',
          'lang_vars' => ['langstr']
        }.merge(config_overrides))
      )
      site.prepare
      site.data = {
        'shared' => 'shared',
        'strings' => { 'hello' => 'hello' },
        'en' => { 'strings' => { 'hello' => 'Hello' } },
        'es' => { 'strings' => { 'hello' => 'Hola' } }
      }
      site
    end

    def page_double(rendered_lang)
      data = rendered_lang.nil? ? {} : { 'rendered_lang' => rendered_lang }
      instance_double(Jekyll::Page, :data => data)
    end

    describe '#full_default_lang_fallback' do
      it 'is disabled by default' do
        expect(prepared_site.full_default_lang_fallback).to be false
      end

      it 'is enabled from config' do
        site = prepared_site('full_default_lang_fallback' => true)
        expect(site.full_default_lang_fallback).to be true
      end
    end

    describe '#localized_data_for' do
      it 'merges the requested language over the default language data' do
        site = prepared_site
        site.active_lang = 'es'
        hook_coordinate(site)

        expect(site.data['strings']['hello']).to eq('Hola')
        expect(site.localized_data_for('en')['strings']['hello']).to eq('Hello')
        expect(site.localized_data_for('en')['shared']).to eq('shared')
        expect(site.localized_data_for('es')['strings']['hello']).to eq('Hola')
      end

      it 'does not mutate the active language data' do
        site = prepared_site
        site.active_lang = 'es'
        hook_coordinate(site)
        site.localized_data_for('en')

        expect(site.data['strings']['hello']).to eq('Hola')
      end
    end

    describe '#fallback_page?' do
      it 'is true when a page is rendered in a different language than the build' do
        site = prepared_site
        site.active_lang = 'es'

        expect(site.fallback_page?(page_double('en'))).to be true
        expect(site.fallback_page?(page_double('es'))).to be false
        expect(site.fallback_page?(page_double(nil))).to be false
      end
    end
  end
end
