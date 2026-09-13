require 'rspec/helper'
require 'ostruct'
require 'fileutils'
require 'tmpdir'
require_relative '../../../../lib/jekyll/polyglot/hooks/coordinate'
Dir.mktmpdir do |_|
  FileUtils.mkdir_p 'css'
  FileUtils.mkdir_p 'images'
  FileUtils.mkdir_p 'javascript'
  describe 'hook_coordinate' do
    before do
      @config = Jekyll::Configuration::DEFAULTS.dup
      @langs = ['en', 'fr', 'es']
      @default_lang = 'en'
      @exclude_from_localization = ['javascript', 'images', 'css/', 'README.md']
      @config['langs'] = @langs
      @config['default_lang'] = @default_lang
      @config['exclude_from_localization'] = @exclude_from_localization
      @parallel_localization = @config['parallel_localization'] || true
      @site = Site.new(
        Jekyll.configuration(
          'languages'                 => @langs,
          'default_lang'              => @default_lang,
          'exclude_from_localization' => @exclude_from_localization,
          'source'                    => File.expand_path('../../../../fixture', __FILE__)
        )
      )
      @site.prepare
      @collection = Jekyll::Collection.new(@site, "fixture")
      @site.data = { 'foo' => 'databar', 'baz' => 'databaz', 'strings' => {
                       'banana' => 'banana'
                     } }
      @site.data['en'] = { 'foo' => 'enbar', 'strings' => {
                             'apple' => 'apple', 'ice cream' => 'ice cream'
                           } }
      @site.data['fr'] = { 'foo' => 'frbar', 'strings' => {
                             'ice cream' => 'crème glacée'
                           } }
    end

    it 'should have trailing / on all dir entries in exclude_from_localization' do
      expect(@site.exclude_from_localization).to eq(["javascript/", "images/", "css/", "README.md"])
    end

    it 'should merge the site.data.active_lang to the site.data' do
      hook_coordinate(@site)
      expect(@site.data['foo']).to eq('enbar')
      expect(@site.data['baz']).to eq('databaz')
      expect(@site.data['strings']['ice cream']).to eq('ice cream')
      expect(@site.data['strings']['apple']).to eq('apple')
      expect(@site.data['strings']['banana']).to eq('banana')
    end

    it 'should fall back to the default_lang when using translated site data' do
      @site.active_lang = 'fr'
      hook_coordinate(@site)
      expect(@site.data['foo']).to eq('frbar')
      expect(@site.data['baz']).to eq('databaz')
      expect(@site.data['strings']['ice cream']).to eq('crème glacée') # Populated from @site.data['strings'][@site.active_lang]['ice cream']
      expect(@site.data['strings']['apple']).to eq('apple') # Populated from @site.data['strings'][@site.default_lang]['apple']
      expect(@site.data['strings']['banana']).to eq('banana') # Populated from @site.data['strings']['apple']
    end

    it "site.process triggers :polyglot, :post_write hook" do
      hook_called = false
      Jekyll::Hooks.register(:polyglot, :post_write) do |_site|
        hook_called = true
      end
      @site.process
      expect(hook_called).to be true
    end

    describe @coordinate_documents do
      it 'test fixtures in the default lang' do
        expect(@site.source).to end_with('spec/fixture')
        @site.process_language 'en'
        expect(@site.pages).to have_attributes(size: 4) # 3 pages + sitemap.xml
        expect(@site.pages.map(&:name)).to include('en.contact.md')
      end

      it 'should include files in the default_lang without active_lang' do
        @site.process_language 'fr'
        expect(@site.pages).to have_attributes(size: 5) # 4 pages + sitemap.xml
        expect(@site.pages.map(&:name)).to include('en.about.md')
      end

      it 'should include files in the active_lang' do
        @site.process_language 'fr'
        expect(@site.pages).to have_attributes(size: 5) # 4 pages + sitemap.xml
        expect(@site.pages.map(&:name)).to include('fr.menu.md', 'fr.members.md', 'fr.contact.md')
        expect(@site.pages.map(&:name)).not_to include('en.contact.md')
      end

      it 'should not include files in the default_lang with the active_lang' do
        @site.process_language 'fr'
        print(@site.pages.map(&:name))
        expect(@site.pages.map(&:name)).not_to include('en.menu.md')
      end

      it 'should not include files in a different lang from the active_lang' do
        @site.process_language 'fr'
        expect(@site.pages.map(&:name)).not_to include('es.menu.md')
      end

      it 'should not be included if the active_lang is not part of the lang-exclusive' do
        @site.process_language 'fr'
        expect(@site.pages.map(&:name)).not_to include('es.samba.md')
      end

      it 'should respect permalinks when page_id is specified' do
        @site.process_language 'en'
        expect(@site.pages.select { |doc| doc.name == 'en.about.md' }.first.permalink).to eq('about')
        expect(@site.pages.select { |doc| doc.name == 'en.menu.md' }.first.permalink).to eq('the-menu')
        expect(@site.pages.select { |doc| doc.name == 'en.contact.md' }.first.permalink).to eq('/contact')
        @site.process_language 'es'
        expect(@site.pages.select { |doc| doc.name == 'es.menu.md' }.first.permalink).to eq('el-menu')
        expect(@site.pages.select { |doc| doc.name == 'es.samba.md' }.first.permalink).to eq('samba')
        @site.process_language 'fr'
        expect(@site.pages.select { |doc| doc.name == 'fr.menu.md' }.first.permalink).to eq('le-menu')
        expect(@site.pages.select { |doc| doc.name == 'fr.members.md' }.first.permalink).to eq('members')
        expect(@site.pages.select { |doc| doc.name == 'fr.contact.md' }.first.permalink).to eq('/nous-contacter')
      end

      it 'should contain permalink_lang when page_id is specified' do
        @site.process_language 'en'
        menu_permalink_lang = @site.pages.select { |doc| doc.name == 'en.menu.md' }.first.data['permalink_lang']
        expect(menu_permalink_lang).to have_attributes(size: 3)
        expect(menu_permalink_lang.keys).to match_array(@site.config['languages'])
        expect(menu_permalink_lang['en']).to eq('the-menu')
        expect(menu_permalink_lang['es']).to eq('el-menu')
        expect(menu_permalink_lang['fr']).to eq('le-menu')
      end
    end

    def build_site(overrides = {})
      site = Site.new(
        Jekyll.configuration(
          {
            'languages' => @langs,
            'default_lang' => @default_lang,
            'exclude_from_localization' => @exclude_from_localization,
            'source' => File.expand_path('../../../../fixture', __FILE__)
          }.merge(overrides)
        )
      )
      site.prepare
      site
    end

    describe 'generate_fallback_pages option' do
      it 'defaults to true: fr pass still approves the en-only about page as a fallback' do
        site = build_site
        site.process_language 'fr'
        expect(site.pages.map(&:name)).to include('en.about.md')
      end

      it 'explicit true: fr pass still approves the en-only about page as a fallback' do
        site = build_site('generate_fallback_pages' => true)
        site.process_language 'fr'
        expect(site.pages.map(&:name)).to include('en.about.md')
      end

      it 'false: fr pass approves menu, members and contact, but not the en-only about page' do
        site = build_site('generate_fallback_pages' => false)
        site.process_language 'fr'
        names = site.pages.map(&:name)
        expect(names).to include('fr.menu.md', 'fr.members.md', 'fr.contact.md')
        expect(names).not_to include('en.about.md')
      end

      it 'false: en pass approves about, menu and contact, but not the fr-exclusive members page' do
        site = build_site('generate_fallback_pages' => false)
        site.process_language 'en'
        names = site.pages.map(&:name)
        expect(names).to include('en.about.md', 'en.menu.md', 'en.contact.md')
        expect(names).not_to include('fr.members.md')
      end

      it 'false: a lang-exclusive document still only ever appears in its exclusive language' do
        site = build_site('generate_fallback_pages' => false)
        site.process_language 'fr'
        expect(site.pages.map(&:name)).to include('fr.members.md')

        site_en = build_site('generate_fallback_pages' => false)
        site_en.process_language 'en'
        expect(site_en.pages.map(&:name)).not_to include('fr.members.md')

        site_es = build_site('generate_fallback_pages' => false)
        site_es.process_language 'es'
        expect(site_es.pages.map(&:name)).not_to include('fr.members.md')
      end

      it 'hreflang on en/about lists only en and x-default; on en/menu lists all three (unchanged)' do
        site = build_site('url' => 'https://example.com')
        site.process_language 'en'
        about = site.pages.find { |doc| doc.name == 'en.about.md' }
        menu = site.pages.find { |doc| doc.name == 'en.menu.md' }

        about_context = Liquid::Context.new({}, {}, { site: site, page: about.data })
        about_output = Liquid::Template.parse('{% i18n_headers %}').render(about_context)
        expect(about_output.scan(/hreflang="([^"]+)"/).flatten).to contain_exactly('en', 'x-default')

        menu_context = Liquid::Context.new({}, {}, { site: site, page: menu.data })
        menu_output = Liquid::Template.parse('{% i18n_headers %}').render(menu_context)
        expect(menu_output.scan(/hreflang="([^"]+)"/).flatten).to contain_exactly('en', 'x-default', 'es', 'fr')
      end
    end

    describe 'canonical_url document data' do
      it "fr pass: sets an /fr-prefixed canonical_url using each document's own url" do
        site = build_site('url' => 'https://example.com')
        site.process_language 'fr'
        menu = site.pages.find { |doc| doc.name == 'fr.menu.md' }
        contact = site.pages.find { |doc| doc.name == 'fr.contact.md' }
        expect(menu.data['canonical_url']).to eq('https://example.com/fr/le-menu')
        expect(contact.data['canonical_url']).to eq('https://example.com/fr/nous-contacter')
      end

      it 'en pass: canonical_url is unprefixed' do
        site = build_site('url' => 'https://example.com')
        site.process_language 'en'
        about = site.pages.find { |doc| doc.name == 'en.about.md' }
        expect(about.data['canonical_url']).to eq('https://example.com/about')
      end

      it 'never overwrites a front-matter canonical_url' do
        site = build_site('url' => 'https://example.com')
        site.process_language 'en'
        collection = Jekyll::Collection.new(site, 'test')
        doc = Jekyll::Document.new('test.md', site: site, collection: collection).tap do |d|
          d.data['lang'] = 'en'
          d.data['permalink'] = '/custom/'
          d.data['canonical_url'] = 'https://mysite.example/pinned/'
        end
        site.coordinate_documents([doc])
        expect(doc.data['canonical_url']).to eq('https://mysite.example/pinned/')
      end

      it 'is absolute and includes the configured baseurl' do
        site = build_site('url' => 'https://example.com', 'baseurl' => '/blog')
        site.process_language 'fr'
        menu = site.pages.find { |doc| doc.name == 'fr.menu.md' }
        expect(menu.data['canonical_url']).to eq('https://example.com/blog/fr/le-menu')
      end
    end
  end
end
