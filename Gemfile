# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

if ENV['USE_LOCAL_CAPABILITY_GATE'] == 'true'
  gem 'wild-capability-gate', path: '../wild-capability-gate'
else
  gem 'wild-capability-gate',
      git: 'https://github.com/jeremylongshore/wild-capability-gate',
      branch: 'main'
end

group :development, :test do
  gem 'rspec', '~> 3.13'
  gem 'rubocop', '~> 1.68', require: false
  gem 'rubocop-rspec', '~> 3.2', require: false
  gem 'sqlite3', '~> 2.0'
end
