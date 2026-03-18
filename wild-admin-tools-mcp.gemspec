# frozen_string_literal: true

require_relative 'lib/wild_admin_tools_mcp/version'

Gem::Specification.new do |spec|
  spec.name = 'wild-admin-tools-mcp'
  spec.version = WildAdminToolsMcp::VERSION
  spec.authors = ['Intent Solutions']
  spec.summary = 'Governed administrative operations for Rails applications via MCP'
  spec.description = 'MCP server providing safe, audited administrative operations for live ' \
                     'Rails applications. Dry-run enforcement, two-phase confirmation, ' \
                     'before/after audit snapshots, blast radius caps, and mandatory capability gating.'
  spec.homepage = 'https://github.com/jeremylongshore/wild-admin-tools-mcp'
  spec.license = 'Nonstandard'
  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*.rb', 'config/**/*.yml', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'activerecord', '>= 7.0', '< 9.0'
  spec.add_dependency 'mcp', '~> 0.8'
  spec.add_dependency 'yaml'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
