# frozen_string_literal: true

require 'yaml'

module Abqari
  class Page
    # File I/O + frontmatter / body parsing. Mixed into Page so the
    # methods operate on Page instance state (`@source_path`,
    # `@frontmatter`, `@body`). Kept here so changes to the on-disk
    # format don't ripple through the rest of Page.
    #
    # `parse` runs once at construction. `load_body_from_file!` re-
    # reads just the body after `forget_body!` has released it.
    module Parser
      private

      # Read the source file, separate frontmatter from body. Sets
      # `@frontmatter` and `@body` together so the first access of
      # either avoids a second I/O.
      def parse
        # `bom|utf-8`: strip a leading UTF-8 BOM if present. Windows
        # editors and some exporters prepend one; without stripping, the
        # `\A---` frontmatter anchor doesn't match and the whole
        # `--- … ---` block renders as visible body text.
        raw = read_source
        if (match = raw.match(FRONTMATTER_RE))
          @frontmatter = parse_frontmatter(match[1])
          @body = match[2]
        else
          @frontmatter = {}
          @body = raw
        end
        # Per-collection normalisation — expands `price: "$16.00"`
        # shorthand into the canonical { cents, currency, formatted }
        # Hash so the rest of the engine never has to think about
        # which form the author used. See docs/publications.md.
        #
        # `collection` requires a full Site (it iterates
        # `site.collections`). Tests that construct a Page against a
        # stub site won't have that — in which case skip
        # normalisation and pass the raw frontmatter through.
        @frontmatter = PublicationNormaliser.call(@frontmatter, safe_collection_for_normalisation)
      end

      def safe_collection_for_normalisation
        collection
      rescue StandardError
        nil
      end

      # Re-read just the body section from disk. Used by `#body` when a
      # prior `forget_body!` has nilled out `@body`. Frontmatter parsing
      # is skipped — we already have it from the initial parse — but we
      # still have to scan past the frontmatter block in the file.
      #
      # Uses `match[2]` (the body capture group) — NOT `match.post_match`.
      # FRONTMATTER_RE's trailing `(.*)/m` greedily eats the body itself,
      # so `post_match` is always the empty string. (The earlier
      # `raw_body` implementation had this bug; it shipped silently
      # because `description` always found an explicit frontmatter
      # value to return first.)
      def load_body_from_file!
        raw = read_source
        @body = if (match = raw.match(FRONTMATTER_RE))
                  match[2]
                else
                  raw
                end
      end

      # Read the source file as UTF-8, stripping a leading BOM. Invalid
      # byte sequences surface with the source path attached rather than
      # a bare `ArgumentError: invalid byte sequence` far from the file.
      def read_source
        raw = File.read(source_path, encoding: 'bom|utf-8')
        # `File.read` tags the string UTF-8 without validating the bytes;
        # an invalid sequence would otherwise blow up later (in a regex
        # match or Commonmarker) with no source path. Check here so the
        # error names the file.
        unless raw.valid_encoding?
          raise "invalid UTF-8 in #{source_path}: file contains bytes that are not valid UTF-8"
        end

        raw
      rescue ArgumentError => e
        raise "invalid encoding in #{source_path}: #{e.message}"
      end

      # Parse the YAML frontmatter block, re-raising on failure with
      # the source path attached. Passing `filename:` to `safe_load`
      # makes Psych embed the path directly in its own error message —
      # turns "did not find expected key at line 4" (which file?) into
      # a specific, actionable error.
      #
      # For other failure modes (Psych::DisallowedClass for un-
      # permitted frontmatter types, IO errors, etc.) the rescue wraps
      # with the path so the operator can find the offending file
      # without grepping.
      def parse_frontmatter(yaml)
        result = load_frontmatter_yaml(yaml)
        # Frontmatter must be a mapping. A bare scalar (`title` typed
        # without a value) or a sequence otherwise flows on as a String
        # or Array — `frontmatter['title']` then does String#[] substring
        # matching (garbage) or raises a TypeError far from the parse.
        unless result.is_a?(Hash)
          raise UserError,
                "frontmatter in #{source_path} must be a mapping (key: value pairs), " \
                "got #{result.class}"
        end
        result
      end

      def load_frontmatter_yaml(yaml)
        YAML.safe_load(yaml,
                       permitted_classes: Abqari::YAML_PERMITTED_CLASSES,
                       filename: source_path) || {}
      rescue Psych::SyntaxError => e
        # `filename:` above puts the path in Psych's message; the line
        # number is relative to the frontmatter block, so say so rather
        # than let the author hunt for line 2 of a 200-line file.
        raise UserError,
              "#{source_path} — invalid YAML in frontmatter at line #{e.line}, " \
              "column #{e.column}: #{e.problem} #{e.context}".strip
      rescue StandardError => e
        raise UserError, "invalid frontmatter in #{source_path}: #{e.class}: #{e.message}"
      end
    end
  end
end
