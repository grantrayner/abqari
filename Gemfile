source 'https://rubygems.org'

ruby '~> 3.3'

gem 'base64', '~> 0.2'    # used by ThemeBootstrap to compute the inline-script CSP hash
gem 'commonmarker', '~> 1.1'
# csv: used by the Substack importer (`bin/import substack`). Moved out
# of Ruby's default gem set in 3.4; pin it explicitly so Bundler's
# frozen-mode CI runs don't fail with a require error.
gem 'csv', '~> 3.3'
gem 'erubi', '~> 1.13'    # auto-escape ERB engine — see docs/security.md §3
gem 'reverse_markdown', '~> 3.0' # HTML→Markdown for `bin/import` (lazy-loaded; no cost on normal builds)
gem 'rouge', '~> 4.0'
gem 'ruby-vips', '~> 2.2' # native libvips bindings for the image pipeline
gem 'webrick', '~> 1.8'

group :development do
  gem 'listen', '~> 3.8'    # FS events for the dev-server watcher (optional)
  gem 'minitest', '~> 5.0'
  # ostruct + rexml: used by the test suite (struct stubs in many tests;
  # XML validation in sitemap_feed_escape_test). Both moved out of Ruby's
  # default gem set on different schedules; pin so CI passes under
  # Bundler's frozen mode regardless of which Ruby minor we're on.
  gem 'ostruct', '~> 0.6'
  gem 'rexml', '~> 3.3'
  gem 'simplecov', '~> 0.22', require: false  # line coverage; opt-in via COVERAGE=1
end
