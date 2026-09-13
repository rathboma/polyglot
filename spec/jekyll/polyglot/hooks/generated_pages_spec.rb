require 'rspec/helper'
require 'fileutils'
require 'tmpdir'
require_relative '../../../../lib/jekyll/polyglot/hooks/coordinate'

# Stands in for a page-generating plugin such as jekyll-archives. Jekyll runs
# generators after the :site, :post_read hook, so the page it creates here is
# never seen by coordinate_documents. Gated on a config flag so it stays inert
# for every other spec in the suite.
class SpecArchiveGenerator < Jekyll::Generator
  def generate(site)
    return unless site.config['spec_generate_archive']

    page = Jekyll::PageWithoutAFile.new(site, site.source, 'category/reviews', 'index.html')
    page.content = 'generated archive'
    page.data['layout'] = nil
    site.pages << page
  end
end

describe 'generated pages' do
  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def build_site(overrides = {})
    site = Site.new(
      Jekyll.configuration(
        {
          'languages' => ['en', 'fr'],
          'default_lang' => 'en',
          'source' => File.expand_path('../../../../fixture', __FILE__),
          'destination' => tmpdir,
          'url' => 'https://example.com',
          'spec_generate_archive' => true
        }.merge(overrides)
      )
    )
    site.prepare
    site
  end

  def generated_page(site)
    site.pages.find { |page| page.url.include?('category/reviews') }
  end

  it 'gives a generator-created page a language-prefixed canonical_url' do
    site = build_site
    site.process_language 'fr'
    page = generated_page(site)

    expect(page).not_to be_nil
    expect(page.data['canonical_url']).to eq('https://example.com/fr/category/reviews/')
  end

  it 'gives a generator-created page a rendered_lang of the pass that built it' do
    site = build_site
    site.process_language 'fr'

    expect(generated_page(site).data['rendered_lang']).to eq('fr')
  end

  it 'leaves a generator-created page unprefixed in the default language pass' do
    site = build_site
    site.process_language 'en'
    page = generated_page(site)

    expect(page.data['canonical_url']).to eq('https://example.com/category/reviews/')
    expect(page.data['rendered_lang']).to eq('en')
  end

  it 'uses the language slug rather than the code for generated pages' do
    site = build_site(
      'languages' => ['en', 'pt-BR'],
      'language_slugs' => { 'pt-BR' => 'pt-br' }
    )
    site.process_language 'pt-BR'
    page = generated_page(site)

    expect(page.data['canonical_url']).to eq('https://example.com/pt-br/category/reviews/')
    # The slug is the path; the code is still the language
    expect(page.data['rendered_lang']).to eq('pt-BR')
  end

  it 'includes the baseurl in a generated page canonical_url' do
    site = build_site('baseurl' => '/blog')
    site.process_language 'fr'

    expect(generated_page(site).data['canonical_url']).to eq('https://example.com/blog/fr/category/reviews/')
  end

  it 'never overwrites a canonical_url the generator set itself' do
    site = build_site
    site.active_lang = 'fr'
    page = Jekyll::PageWithoutAFile.new(site, site.source, 'pinned', 'index.html')
    page.data['canonical_url'] = 'https://mysite.example/pinned/'
    site.pages << page

    site.coordinate_generated_documents

    expect(page.data['canonical_url']).to eq('https://mysite.example/pinned/')
  end

  it 'leaves metadata assigned by coordinate_documents alone' do
    site = build_site
    site.process_language 'fr'
    # fr.menu.md is a real translation, coordinated at :site, :post_read
    menu = site.pages.find { |page| page.respond_to?(:name) && page.name == 'fr.menu.md' }

    expect(menu.data['rendered_lang']).to eq('fr')
    expect(menu.data['canonical_url']).to eq('https://example.com/fr/le-menu')
  end
end
