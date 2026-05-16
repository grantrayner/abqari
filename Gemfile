source 'https://rubygems.org'

ruby '~> 3.3'

gem 'base64', '~> 0.2'    # used by ThemeBootstrap to compute the inline-script CSP hash
gem 'commonmarker', '~> 1.1'
gem 'erubi', '~> 1.13'    # auto-escape ERB engine — see docs/security.md §3
gem 'rouge', '~> 4.0'
gem 'ruby-vips', '~> 2.2' # native libvips bindings for the image pipeline
gem 'webrick', '~> 1.8'

group :development do
  gem 'listen', '~> 3.8'    # FS events for the dev-server watcher (optional)
  gem 'minitest', '~> 5.0'
  gem 'simplecov', '~> 0.22', require: false  # line coverage; opt-in via COVERAGE=1
end
