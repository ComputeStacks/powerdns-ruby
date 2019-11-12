# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pdns/version'

Gem::Specification.new do |spec|
  spec.name          = "pdns"
  spec.version       = Pdns::VERSION
  spec.authors       = ["Kris Watson"]
  spec.email         = ["kris@computestacks.com"]

  spec.summary       = "PowerDNS Module for ComputeStacks"
  spec.description   = "PowerDNS Module for ComputeStacks"
  spec.homepage      = "https://wwww.computestacks.com"

  spec.add_dependency 'json', "~> 2.1"
  spec.add_dependency 'httparty', '>= 0.17.0'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.17"
  spec.add_development_dependency "rake", ">= 12.0"
end
