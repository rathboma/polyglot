require 'rspec/helper'
require 'fileutils'
require 'tmpdir'
require_relative '../../../../lib/jekyll/polyglot/hooks/coordinate'

# With generate_fallback_pages off, a link to a page this language doesn't have
# would otherwise be relativized to a URL that was never generated - a 301 at
# best, a 404 without a host catch-all. These pin that links to missing pages
# are left pointing at the default language, and that everything else still
# relativizes exactly as before.
describe 'relativizing links to untranslated pages' do
  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def build_site(overrides = {})
    site = Site.new(
      Jekyll.configuration(
        {
          'languages' => ['en', 'fr', 'es'],
          'default_lang' => 'en',
          'source' => File.expand_path('../../../../fixture', __FILE__),
          'destination' => tmpdir,
          'url' => 'https://example.com'
        }.merge(overrides)
      )
    )
    site.prepare
    site
  end

  def relativized(site, html)
    collection = Jekyll::Collection.new(site, 'test')
    doc = Jekyll::Document.new('test.md', site: site, collection: collection)
    doc.output = html
    site.relativize_urls(doc, site.relative_url_regex)
    doc.output
  end

  def relativized_absolute(site, html)
    collection = Jekyll::Collection.new(site, 'test')
    doc = Jekyll::Document.new('test.md', site: site, collection: collection)
    doc.output = html
    site.relativize_absolute_urls(doc, site.absolute_url_regex('https://example.com'), 'https://example.com')
    doc.output
  end

  context 'with generate_fallback_pages false' do
    let(:site) do
      site = build_site('generate_fallback_pages' => false)
      site.process_language 'fr'
      site
    end

    it 'leaves a link to a page with no translation pointing at the default language' do
      # about exists only in en, so /fr/about was never generated
      expect(relativized(site, 'href="/about"')).to eq('href="/about"')
    end

    it 'still relativizes a link to a page that does have a translation' do
      # le-menu is the fr version of the menu page
      expect(relativized(site, 'href="/le-menu"')).to eq('href="/fr/le-menu"')
    end

    it 'leaves a link to a page exclusive to another language alone' do
      # samba is lang-exclusive to es
      expect(relativized(site, 'href="/samba"')).to eq('href="/samba"')
    end

    it 'matches regardless of a trailing slash or anchor' do
      expect(relativized(site, 'href="/about/"')).to eq('href="/about/"')
      expect(relativized(site, 'href="/about/#team"')).to eq('href="/about/#team"')
    end

    it 'still relativizes links to things it knows nothing about' do
      # assets and generator-created pages never pass through coordination,
      # so they keep the existing behaviour rather than being guessed at
      expect(relativized(site, 'href="/category/reviews/"')).to eq('href="/fr/category/reviews/"')
    end

    it 'applies the same rule to absolute urls' do
      expect(relativized_absolute(site, 'href="https://example.com/about"'))
        .to eq('href="https://example.com/about"')
      expect(relativized_absolute(site, 'href="https://example.com/le-menu"'))
        .to eq('href="https://example.com/fr/le-menu"')
    end
  end

  context 'with fallback pages left on (the default)' do
    let(:site) do
      site = build_site
      site.process_language 'fr'
      site
    end

    it 'relativizes every link, since every page exists in every language' do
      expect(relativized(site, 'href="/about"')).to eq('href="/fr/about"')
      expect(relativized(site, 'href="/le-menu"')).to eq('href="/fr/le-menu"')
    end
  end

  context 'when in the default language pass' do
    it 'never rewrites links, fallbacks on or off' do
      site = build_site('generate_fallback_pages' => false)
      site.process_language 'en'

      collection = Jekyll::Collection.new(site, 'test')
      doc = Jekyll::Document.new('test.md', site: site, collection: collection)
      doc.output = 'href="/about" href="/le-menu"'
      site.process_documents([doc])

      expect(doc.output).to eq('href="/about" href="/le-menu"')
    end
  end
end
