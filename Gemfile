source 'https://rubygems.org'

ruby '>= 3.3'   # matches abqari.gemspec's required_ruby_version

# Runtime dependencies live in abqari.gemspec — the single source of
# truth for what the published gem declares. The `gemspec` directive
# pulls them in here so CI always tests exactly the constraints the
# gem ships with; listing them in both files invites silent drift.
gemspec

group :development do
  gem 'listen', '~> 3.8'    # FS events for the dev-server watcher (optional)
  gem 'minitest', '~> 5.0'
  # ostruct + rexml: used by the test suite (struct stubs in many tests;
  # XML validation in sitemap_feed_escape_test). Both moved out of Ruby's
  # default gem set on different schedules; pin so CI passes under
  # Bundler's frozen mode regardless of which Ruby minor we're on.
  gem 'ostruct', '~> 0.6'
  gem 'rexml', '~> 3.3'
  gem 'simplecov', '~> 1.0', require: false   # line coverage; opt-in via COVERAGE=1
end
