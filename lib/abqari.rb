# frozen_string_literal: true

require 'date'
require 'time'

module Abqari
  ROOT = File.expand_path('..', __dir__)
  VERSION = '0.3.0'

  # Classes the engine accepts from any YAML input — site config,
  # data files, frontmatter, Folio cache, audit whitelists. Date +
  # Time so naked dates like `date: 2026-06-15` and ISO timestamps
  # round-trip. Anything else (Symbol, ranges, arbitrary classes)
  # raises Psych::DisallowedClass before any deserialised object
  # touches the engine. Keep this set minimal — adding a class here
  # is the security-sensitive equivalent of widening a sandbox.
  YAML_PERMITTED_CLASSES = [Date, Time].freeze

  # Jekyll-style YAML frontmatter — opening `---`, body, closing
  # `---`, then everything after.
  #
  # Match groups:
  #   [1] = the YAML body between the `---` markers
  #   [2] = everything after the closing `---\n` (page body / layout
  #         markup / whatever follows)
  #
  # Used in three places — Page (content files), RenderContext (layout
  # files chaining via `layout:`), and Renderer (parent-layout lookup
  # for the dep-mtime walker). Centralised here so the three callers
  # stay in lockstep; previously the regex was duplicated and one copy
  # had drifted (no body capture group), which made consolidation
  # easy to put off.
  FRONTMATTER_RE = /\A---\s*\n(.*?\n)---\s*\n(.*)/m.freeze
end

require_relative 'abqari/log'
require_relative 'abqari/hooks'
require_relative 'abqari/path_safe'
require_relative 'abqari/http_safe'
require_relative 'abqari/site_config'
require_relative 'abqari/erbi_template'
require_relative 'abqari/helpers'
require_relative 'abqari/render_context'
require_relative 'abqari/paginator'
require_relative 'abqari/publication_normaliser'
require_relative 'abqari/page'
require_relative 'abqari/taxonomy_page'
require_relative 'abqari/paginated_shard'
require_relative 'abqari/asset_pipeline'
require_relative 'abqari/bundle_assets'
require_relative 'abqari/font_pipeline'
require_relative 'abqari/sitemap'
require_relative 'abqari/feed'
require_relative 'abqari/robots'
require_relative 'abqari/headers_file'
require_relative 'abqari/manifest'
require_relative 'abqari/llms_txt'
require_relative 'abqari/og_image_generator'
require_relative 'abqari/security_txt'
require_relative 'abqari/redirects'
require_relative 'abqari/image_pipeline'
require_relative 'abqari/minifier'
require_relative 'abqari/search'
require_relative 'abqari/syntax_highlighter'
require_relative 'abqari/theme_bootstrap'
require_relative 'abqari/speculation_rules_guard'
require_relative 'abqari/plausible_script'
require_relative 'abqari/visualizations'
require_relative 'abqari/folio'
require_relative 'abqari/folio_pages'
require_relative 'abqari/related_index_page'
require_relative 'abqari/site'
require_relative 'abqari/audit'
require_relative 'abqari/server'
