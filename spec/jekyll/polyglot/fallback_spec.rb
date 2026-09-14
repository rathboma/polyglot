require 'rspec/helper'
require 'fileutils'
require 'tmpdir'

# Builds the spec fixture site, which contains
#   - an /about/ page written only in the default language
#   - a /menu/ page translated into english, spanish and french
#   - a post translated into english and french, but not spanish
#   - /samba/ and /members/ pages that name their languages with lang-exclusive
describe 'fallback page generation' do
  def fixture_path
    File.expand_path('../../../fixture', __FILE__)
  end

  # builds a throwaway copy of the fixture site, so a test can add pages of
  # its own without disturbing the fixture every other spec reads
  def build_site(config = {}, extra_pages = {})
    source = Dir.mktmpdir('polyglot-fallback-src')
    dest = Dir.mktmpdir('polyglot-fallback-dest')
    FileUtils.cp_r(File.join(fixture_path, '.'), source)
    FileUtils.rm_rf(File.join(source, '_site'))
    FileUtils.rm_rf(File.join(source, '.jekyll-cache'))
    extra_pages.each do |path, contents|
      File.write(File.join(source, path), contents)
    end
    site = Site.new(
      Jekyll.configuration({
        'languages' => ['en', 'es', 'fr'],
        'default_lang' => 'en',
        'exclude_from_localization' => ['javascript', 'images', 'css', 'public'],
        'source' => source,
        'destination' => dest,
        'url' => 'http://localhost:4000',
        'include' => ['pages'],
        'collections' => {
          'pages' => { 'output' => true },
          'posts' => { 'output' => true }
        }
      }.merge(config))
    )
    silence_stdout { site.process }
    FileUtils.rm_rf(source)
    dest
  end

  def page_with_frontmatter(title, permalink, frontmatter)
    <<~PAGE
      ---
      title: #{title}
      permalink: #{permalink}
      lang: en
      #{frontmatter}
      ---

      # #{title}
    PAGE
  end

  def built?(dest, path)
    File.exist?(File.join(dest, path))
  end

  # rubocop:disable RSpec/BeforeAfterAll
  before(:all) do
    @with_fallback = build_site
    @without_fallback = build_site('fallback_to_default_lang' => false)
  end

  after(:all) do
    FileUtils.rm_rf(@with_fallback)
    FileUtils.rm_rf(@without_fallback)
  end
  # rubocop:enable RSpec/BeforeAfterAll

  describe 'with fallback pages enabled' do
    it 'builds an untranslated page in every language' do
      expect(built?(@with_fallback, 'about.html')).to be true
      expect(built?(@with_fallback, 'es/about.html')).to be true
      expect(built?(@with_fallback, 'fr/about.html')).to be true
    end

    it 'builds an untranslated post in every language' do
      expect(built?(@with_fallback, '2020/01/01/test-post.html')).to be true
      expect(built?(@with_fallback, 'es/2020/01/01/test-post.html')).to be true
      expect(built?(@with_fallback, 'fr/2020/01/01/test-post.html')).to be true
    end
  end

  describe 'with fallback pages disabled' do
    it 'builds an untranslated page in its own language only' do
      expect(built?(@without_fallback, 'about.html')).to be true
      expect(built?(@without_fallback, 'es/about.html')).to be false
      expect(built?(@without_fallback, 'fr/about.html')).to be false
    end

    it 'builds a post only in the languages it has been translated into' do
      expect(built?(@without_fallback, '2020/01/01/test-post.html')).to be true
      expect(built?(@without_fallback, 'fr/2020/01/01/test-post.html')).to be true
      expect(built?(@without_fallback, 'es/2020/01/01/test-post.html')).to be false
    end

    it 'builds a translated page in every language it is translated into' do
      expect(built?(@without_fallback, 'the-menu.html')).to be true
      expect(built?(@without_fallback, 'es/el-menu.html')).to be true
      expect(built?(@without_fallback, 'fr/le-menu.html')).to be true
    end

    it 'still builds the languages a document names with lang-exclusive' do
      expect(built?(@without_fallback, 'es/samba.html')).to be true
      expect(built?(@without_fallback, 'fr/members.html')).to be true
    end
  end

  describe 'fallback frontmatter' do
    it 'keeps a page in every language when the site has fallbacks off' do
      dest = build_site(
        { 'fallback_to_default_lang' => false },
        { 'pages/en.contact.md' => page_with_frontmatter('Contact', 'contact', 'fallback: true') }
      )

      expect(built?(dest, 'contact.html')).to be true
      expect(built?(dest, 'es/contact.html')).to be true
      expect(built?(dest, 'fr/contact.html')).to be true
      FileUtils.rm_rf(dest)
    end

    it 'keeps a page out of other languages when the site has fallbacks on' do
      dest = build_site(
        {},
        { 'pages/en.contact.md' => page_with_frontmatter('Contact', 'contact', 'fallback: false') }
      )

      expect(built?(dest, 'contact.html')).to be true
      expect(built?(dest, 'es/contact.html')).to be false
      expect(built?(dest, 'fr/contact.html')).to be false
      FileUtils.rm_rf(dest)
    end
  end
end
