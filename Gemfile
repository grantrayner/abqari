source 'https://rubygems.org'

ruby '>= 3.3'   # matches abqari.gemspec's required_ruby_version

# Runtime dependencies live in abqari.gemspec — the single source of
# truth for what the published gem declares. The `gemspec` directive
# pulls them in here so CI always tests exactly the constraints the
# gem ships with; listing them in both files invites silent drift.
gemspec

group :development do
  # bundler-audit: the CVE check in `bin/check` and both CI workflows.
  # In the bundle rather than a global `gem install` so it's pinned,
  # reviewable via Dependabot, and — the reason it moved here — present
  # regardless of which Ruby is active. A global install belongs to one
  # Ruby, so switching from 3.3 to 4.0 silently broke `bin/check`'s CVE
  # step with "command not found". `require: false`: it's a CLI, never
  # loaded in-process.
  gem 'bundler-audit', '~> 0.9', require: false
  gem 'listen', '~> 3.10'   # FS events for the dev-server watcher (optional)
  gem 'minitest', '~> 5.0'
  # reverse_markdown is an OPTIONAL runtime dependency (see the gemspec
  # for why it isn't declared there) — but the engine's own test suite
  # exercises the importers, so it's needed to develop against.
  gem 'reverse_markdown', '~> 2.1'
  # ostruct + rexml: used by the test suite (struct stubs in many tests;
  # XML validation in sitemap_feed_escape_test). Both moved out of Ruby's
  # default gem set on different schedules; pin so CI passes under
  # Bundler's frozen mode regardless of which Ruby minor we're on.
  gem 'ostruct', '~> 0.6'
  gem 'rexml', '~> 3.3'
  gem 'simplecov', '~> 0.22', require: false  # line coverage; opt-in via COVERAGE=1
end
