# frozen_string_literal: true

module Abqari
  # Content importers — `bin/import <platform> <source>`.
  #
  # Loaded lazily: the registry below maps platform names to file
  # paths so a normal site build never pays the cost of pulling
  # reverse_markdown + the per-platform parsers into memory. The
  # CLI handler resolves the requested platform and requires only
  # its file.
  #
  # Adding a new importer:
  #   1. Create `lib/abqari/importers/<name>.rb` with class
  #      `Abqari::Importers::<Name>` < `Base`.
  #   2. Register it in `REGISTRY` below with its short name.
  #   3. Add a one-line description for the `--help` text.
  #
  # Each importer implements `each_post` yielding `Base::ImportedPost`
  # records. The base class handles the rest: HTML→Markdown,
  # image download, slug collisions, frontmatter assembly, idempotent
  # writes, and the run report.
  module Importers
    REGISTRY = {
      'substack' => {
        file:        'abqari/importers/substack',
        class_name:  'Abqari::Importers::Substack',
        description: 'Import a Substack export zip (or unzipped directory)'
      },
      'ghost' => {
        file:        'abqari/importers/ghost',
        class_name:  'Abqari::Importers::Ghost',
        description: 'Import a Ghost JSON export'
      },
      'jekyll' => {
        file:        'abqari/importers/jekyll',
        class_name:  'Abqari::Importers::Jekyll',
        description: 'Import a Jekyll site directory (_posts/ + assets)'
      }
    }.freeze

    # Resolve a platform name to an importer class, lazy-loading
    # the file on first use. Returns nil for unknown platforms.
    def self.lookup(platform)
      entry = REGISTRY[platform.to_s]
      return nil unless entry

      require entry[:file]
      Object.const_get(entry[:class_name])
    end

    def self.platforms
      REGISTRY.keys
    end
  end
end

# Support modules are tiny; eager-load them when any importer is
# pulled in. The platform-specific files (substack, ghost, jekyll)
# stay lazy.
require_relative 'importers/support/slug_normalizer'
require_relative 'importers/support/html_to_markdown'
require_relative 'importers/support/image_downloader'
require_relative 'importers/support/report'
require_relative 'importers/base'
