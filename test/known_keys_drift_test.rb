# frozen_string_literal: true

require_relative 'test_helper'

# Static-analysis guard for `SiteConfig::KNOWN_KEYS` drift.
#
# `lib/abqari/site_config.rb` allow-lists every top-level config key
# the engine reads anywhere — the validator uses it to flag typos in
# `config/site.yml`. The allow-list is maintained by hand. When a new
# feature reads a new top-level key but forgets to update KNOWN_KEYS,
# every consuming site that has the key set with `ABQARI_STRICT_CONFIG`
# enabled would suddenly error on the upgrade.
#
# This test reads `lib/` and `app/views/` for top-level config access
# patterns and fails if any referenced key is missing from KNOWN_KEYS.
# Adding a key here is one place to edit; the test catches the drift
# that the doc-comment used to only ask CI to catch.
#
# Out-of-scope: nested config keys (e.g. `config.dig('folio',
# 'base_url')` only checks `folio`), and references where the
# receiver isn't obviously the site config (`cfg['per_page']` etc.
# routinely reads sub-hashes; we don't try to follow those).
class KnownKeysDriftTest < Minitest::Test
  ROOTS = %w[lib app/views].freeze
  EXTS  = %w[.rb .erb].freeze

  # Patterns that pull a top-level key out of the site config.
  # Each match's `key` capture is one top-level site.yml key.
  #
  # Only `site.config[...]` and `@site.config[...]` are considered —
  # `@cfg` / `@config` / bare `config[...]` outside Site are routinely
  # sub-hashes (`@cfg = site.config['folio']`, `@cfg['base_url']` is a
  # Folio sub-key, not a top-level one). Inside `lib/abqari/site.rb`
  # the implicit-self `config[...]` form is handled by
  # `SITE_INTERNAL_PATTERNS` below.
  PATTERNS = [
    /(?:@site\.config|site\.config)\['(?<key>[a-z_][a-z0-9_]*)'\]/,
    /(?:@site\.config|site\.config)\.dig\(\s*'(?<key>[a-z_][a-z0-9_]*)'/
  ].freeze

  # Inside `lib/abqari/site.rb` only, an additional pattern: a bare
  # `config[...]` refers to `self.config`. Scanning this everywhere
  # would false-match sub-hashes (`cfg = collection_config(...);
  # cfg['layout']`). Pinning the pattern to site.rb gives us the
  # remaining top-level reads without the noise.
  SITE_INTERNAL_PATTERNS = [
    /(?<![a-zA-Z_\.])config\['(?<key>[a-z_][a-z0-9_]*)'\]/,
    /(?<![a-zA-Z_\.])config\.dig\(\s*'(?<key>[a-z_][a-z0-9_]*)'/
  ].freeze

  def test_no_unknown_top_level_config_keys_in_source
    referenced = scan_referenced_keys

    known = Abqari::SiteConfig::KNOWN_KEYS.map(&:to_s).to_set
    drift = referenced - known - reserved_prefix_keys(referenced)

    assert drift.empty?, <<~MSG
      Found #{drift.size} top-level config key(s) referenced in source
      but missing from `SiteConfig::KNOWN_KEYS` (lib/abqari/site_config.rb):

        #{drift.sort.join(', ')}

      Each of these would fire an "Unknown config key" warning
      (or error under ABQARI_STRICT_CONFIG=true) the first time a
      consuming site sets the key in its config/site.yml. Add the
      key to KNOWN_KEYS, then re-run.
    MSG
  end

  def test_every_known_key_is_actually_read
    # Inverse direction: every key in KNOWN_KEYS should appear in at
    # least one source file. A key that's allow-listed but never read
    # is dead weight — flag it so the list stays trimmed.
    referenced = scan_referenced_keys

    known = Abqari::SiteConfig::KNOWN_KEYS.map(&:to_s).to_set
    unused = known - referenced - structural_keys

    assert unused.empty?, <<~MSG
      Found #{unused.size} key(s) in `SiteConfig::KNOWN_KEYS` that
      no source file actually reads:

        #{unused.sort.join(', ')}

      Either remove them from KNOWN_KEYS, or — if they're consumed
      from a partial via a helper method that the scan can't detect
      — add them to `structural_keys` below with a rationale.
    MSG
  end

  private

  def scan_referenced_keys
    referenced = Set.new
    each_source_file do |path, source|
      PATTERNS.each do |pattern|
        source.scan(pattern) { referenced << Regexp.last_match[:key] }
      end

      # Bare `config[...]` is only safe to scan inside Site itself.
      next unless path == 'lib/abqari/site.rb'

      SITE_INTERNAL_PATTERNS.each do |pattern|
        source.scan(pattern) { referenced << Regexp.last_match[:key] }
      end
    end
    referenced
  end

  def each_source_file
    ROOTS.each do |root|
      Dir.glob(File.join(root, '**', '*')).each do |path|
        next unless File.file?(path)
        next unless EXTS.include?(File.extname(path))

        yield path, File.read(path, encoding: 'UTF-8')
      end
    end
  end

  # `x_`-prefixed keys are reserved for user extensions per
  # docs/security.md §1 and the SiteConfig comment. They're never
  # going to appear in KNOWN_KEYS by design.
  def reserved_prefix_keys(referenced)
    referenced.select { |k| k.start_with?('x_') }.to_set
  end

  # Keys that are read via mechanisms the simple regex scan can't see —
  # structural config (`environments:` is deleted by SiteLoader and
  # never goes through `config['environments']`), or keys that appear
  # in fixture content rather than engine source. Each entry should
  # carry a one-line rationale in a comment.
  def structural_keys
    Set[
      # `environments:` is consumed by SiteLoader#load_config via
      # `raw.delete('environments')` — it never appears as a
      # `config['environments']` reference, but the validator still
      # has to allow it as a known top-level key.
      'environments',
      # `deploy:` is read by the site-level bin/deploy script
      # (site.config.dig('deploy', ...)), which lives outside the
      # lib/ + app/views scan roots.
      'deploy'
    ]
  end
end
