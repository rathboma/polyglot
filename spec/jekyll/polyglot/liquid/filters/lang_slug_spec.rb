require 'rspec/helper'

describe 'lang_slug filter' do
  def build_site(overrides = {})
    site = Site.new(
      Jekyll.configuration(
        {
          'languages' => ['en', 'pt-BR'],
          'default_lang' => 'en',
          'source' => File.expand_path('../../../../fixture', __dir__),
          'url' => 'https://example.com',
          'language_slugs' => { 'pt-BR' => 'pt-br' }
        }.merge(overrides)
      )
    )
    site.prepare
    site
  end

  def render(template, site)
    assigns = { 'site' => { 'languages' => site.languages, 'default_lang' => site.default_lang } }
    context = Liquid::Context.new(assigns, {}, { site: site, page: {} })
    Liquid::Template.parse(template).render!(context)
  end

  it 'renders the slug for a mapped language' do
    expect(render("{{ 'pt-BR' | lang_slug }}", build_site)).to eq('pt-br')
  end

  it 'renders the code unchanged for an unmapped language' do
    expect(render("{{ 'en' | lang_slug }}", build_site)).to eq('en')
  end

  it 'is unchanged when no language_slugs are configured' do
    site = build_site('language_slugs' => {})
    expect(render("{{ 'pt-BR' | lang_slug }}", site)).to eq('pt-BR')
  end

  it 'builds a language switcher href that points at the real path' do
    template = "{% for lang in site.languages %}<a href=\"/{{ lang | lang_slug }}/about\"></a>{% endfor %}"
    output = render(template, build_site)

    expect(output).to include('href="/pt-br/about"')
    expect(output).not_to include('/pt-BR/')
  end

  it 'leaves the value alone when the site is not a polyglot site' do
    context = Liquid::Context.new({}, {}, { site: Object.new, page: {} })
    output = Liquid::Template.parse("{{ 'pt-BR' | lang_slug }}").render!(context)

    expect(output).to eq('pt-BR')
  end
end
