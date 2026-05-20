# frozen_string_literal: true

module Abqari
  module Importers
    module Support
      # Slug normalisation + collision resolution shared by every
      # importer. The slug rules match `bin/new`'s `slugify` (lowercase,
      # `[^a-z0-9]+` collapsed to a single dash, leading/trailing dashes
      # stripped) so imported posts are indistinguishable from posts
      # authored fresh via the generator.
      #
      # Collision policy is "append a numeric suffix" — `foo`, `foo-2`,
      # `foo-3`. The user picked this over date-prefixing because
      # date-prefixing makes URLs uglier and the source platforms
      # (Substack especially) sometimes reuse slugs deliberately. The
      # appended suffix preserves the original slug as the canonical
      # form when there's no conflict.
      module SlugNormalizer
        module_function

        # Strip a slug down to the engine's canonical shape. ASCII-fold
        # is intentionally omitted — non-ASCII characters are dropped
        # rather than transliterated, matching `bin/new`'s behaviour.
        # Callers that need transliteration (e.g. an importer pulling
        # from a CJK source) should pre-process before calling this.
        def normalize(text)
          text.to_s
              .downcase
              .gsub(/[^a-z0-9]+/, '-')
              .gsub(/\A-|-\z/, '')
        end

        # Resolve a slug against an in-memory set of already-taken
        # slugs. Mutates the set as a side-effect — the resolved slug
        # is added so subsequent calls in the same run see it. This is
        # a pure-in-memory check, distinct from the on-disk collision
        # check that the writer applies separately (filesystem state
        # can change between importer invocations).
        def resolve(slug, taken)
          slug = 'untitled' if slug.to_s.empty?
          candidate = slug
          n = 2
          while taken.include?(candidate)
            candidate = "#{slug}-#{n}"
            n += 1
          end
          taken << candidate
          candidate
        end
      end
    end
  end
end
