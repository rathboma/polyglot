# hook to coordinate blog posts and pages into distinct urls,
# and remove duplicate multilanguage posts and pages
Jekyll::Hooks.register :site, :post_read do |site|
  hook_coordinate(site)
end

def hook_coordinate(site)
  # Copy the language specific data, by recursively merging it with the default
  # data. Favour active_lang first, then default_lang, then any
  # non-language-specific data.
  site.localize_data

  site.collections.each_value do |collection|
    collection.docs = site.coordinate_documents(collection.docs)
  end
  site.pages = site.coordinate_documents(site.pages)
end
