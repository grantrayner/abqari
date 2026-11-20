#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Cloudflare's automatic installer can lag a new Ruby security release.
# Use mise's portable Ruby provider, pinned to an immutable build and digest.
# Update the version, release URL, and checksum together for the next release.
version=4.0.10
checksum=ca54d2d9204f9f9724f7aa1620b30538723da3a9365d9195951b82fa6765fd4e
url=https://github.com/jdx/ruby/releases/download/4.0.10-1/ruby-4.0.10.x86_64_linux.tar.gz

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo 'This bootstrap targets Cloudflare and GitHub Ubuntu x86_64 builds.' >&2
  exit 1
}
[[ "$(tr -d '[:space:]' < .ruby-version)" == "$version" ]] || {
  echo 'Refresh the Cloudflare Ruby bootstrap for the version in .ruby-version.' >&2
  exit 1
}

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT
curl --fail --show-error --location --retry 3 --output "$temporary_dir/ruby.tar.gz" "$url"
printf '%s  %s\n' "$checksum" "$temporary_dir/ruby.tar.gz" | sha256sum --check --status
mkdir "$temporary_dir/ruby"
tar -xzf "$temporary_dir/ruby.tar.gz" --strip-components=1 -C "$temporary_dir/ruby"
export PATH="$temporary_dir/ruby/bin:$PATH"
[[ "$(ruby -e 'print RUBY_VERSION')" == "$version" ]]
ruby --version

bundler_version=$(awk '/^BUNDLED WITH$/ { getline; print $1 }' Gemfile.lock)
gem install bundler --version "$bundler_version" --no-document
export BUNDLE_FROZEN=true
bundle install --jobs 2 --retry 3
ABQARI_ENV=production bundle exec bin/build
