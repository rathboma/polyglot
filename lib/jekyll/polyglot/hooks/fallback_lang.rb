# hooks to render a fallback page in the language its content is written in,
# rather than in the language the site is being built for.
#
# Polyglot builds one copy of the site per language.  A page with no
# translation for the language being built is served as fallback content, so
# its body is in another language while everything keyed off site.active_lang
# (the lang_vars and the localized site.data) is still in the language being
# built, leaving a page that is half one language and half the other.
#
# When full_default_lang_fallback is enabled those variables follow
# page.rendered_lang instead, and the pair is put back the way it was once the
# page and its layouts have rendered.  site.build_lang always reports the
# language the site is being built for.
#
# The swap runs first and the restore runs last so that any other plugin
# rendering a page sees a single consistent language for that page.
Jekyll::Hooks.register :documents, :pre_render, :priority => :high do |doc, payload|
  hook_fallback_lang(doc.site, doc, payload)
end

Jekyll::Hooks.register :pages, :pre_render, :priority => :high do |page, payload|
  hook_fallback_lang(page.site, page, payload)
end

Jekyll::Hooks.register :documents, :post_render, :priority => :low do |doc|
  hook_restore_lang(doc.site)
end

Jekyll::Hooks.register :pages, :post_render, :priority => :low do |page|
  hook_restore_lang(page.site)
end

def hook_fallback_lang(site, doc, payload)
  site.use_rendered_lang(doc, payload)
end

def hook_restore_lang(site)
  site.restore_active_lang
end
