# frozen_string_literal: true

require 'date'
require 'time'

module Abqari
  ROOT = File.expand_path('..', __dir__)
  VERSION = '1.0.0'

  # Classes the engine accepts from any YAML input — site config,
  # data files, frontmatter, Folio cache, audit whitelists. Date +
  # Time so naked dates like `date: 2026-06-15` and ISO timestamps
  # round-trip. Anything else (Symbol, ranges, arbitrary classes)
  # raises Psych::DisallowedClass before any deserialised object
  # touches the engine. Keep this set minimal — adding a class here
  # is the security-sensitive equivalent of widening a sandbox.
  YAML_PERMITTED_CLASSES = [Date, Time].freeze

  # Marker file written by `Site#build` at the end of a successful
  # build. Deployers (`bin/deploy`, CI pipelines that rsync `_site/`)
  # refuse to ship without it; the test harness uses it as the
  # fixture-intact sentinel. Single source of truth so the three
  # readers stay in lockstep.
  BUILD_OK_SENTINEL = '.abqari-build-ok'

  # Atomic file write: write to a sibling tempfile, fsync, then
  # rename into place. POSIX guarantees the rename is atomic on the
  # same filesystem, so a reader either sees the previous full
  # contents or the new full contents — never a half-written buffer.
  #
  # Used for state files we re-read on subsequent builds: the
  # POSSE sent log, the webmention sender log, the webmention
  # cache, the etag pointer. Without atomicity, a SIGINT or
  # runner timeout mid-write leaves a truncated YAML / JSON file
  # and the next build either crashes on parse or — worse for the
  # POSSE case — treats every prior send as un-sent and re-posts
  # everything to Mastodon + Bluesky.
  def self.atomic_write(path, content)
    dir  = File.dirname(path)
    base = File.basename(path)
    tmp  = File.join(dir, ".#{base}.#{Process.pid}.tmp")
    File.open(tmp, 'w') do |f|
      f.write(content)
      f.flush
      f.fsync rescue nil
    end
    File.rename(tmp, path)
  ensure
    File.unlink(tmp) if tmp && File.exist?(tmp) rescue nil
  end

  # Jekyll-style YAML frontmatter — opening `---`, body, closing
  # `---`, then everything after.
  #
  # Match groups:
  #   [1] = the YAML body between the `---` markers
  #   [2] = everything after the closing `---\n` (page body / layout
  #         markup / whatever follows)
  #
  # The YAML group is OPTIONAL (`(?:.*?\n)?`) so an EMPTY frontmatter
  # block (`---\n---\n`) still matches — group [1] is "" (→ `{}` after
  # safe_load), not treated as "no frontmatter" (which rendered the two
  # `---` lines as visible body text).
  #
  # Used in three places — Page (content files), RenderContext (layout
  # files chaining via `layout:`), and Renderer (parent-layout lookup
  # for the dep-mtime walker). Centralised here so the three callers
  # stay in lockstep; previously the regex was duplicated and one copy
  # had drifted (no body capture group), which made consolidation
  # easy to put off.
  FRONTMATTER_RE = /\A---\s*\n((?:.*?\n)?)---\s*\n(.*)/m.freeze
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
require_relative 'abqari/indieweb'
require_relative 'abqari/syndication'
require_relative 'abqari/publisher_pages'
require_relative 'abqari/related_index_page'
require_relative 'abqari/site'
require_relative 'abqari/audit'
require_relative 'abqari/server'
