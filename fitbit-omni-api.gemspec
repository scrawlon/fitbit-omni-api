# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "fitbit-omni-api/version"

Gem::Specification.new do |s|
  s.name        = "fitbit-omni-api"
  s.version     = OmniAuth::Fitbit::Api::VERSION
  s.authors     = ["TK Gospodinov", "Scott McGrath"]
  s.email       = ["tk@gospodinov.net", "acid64k@yahoo.com"]
  s.homepage    = "http://github.com/scrawlon/fitbit-omni-api"
  s.summary     = %q{Fitbit OmniAuth strategy + API wrapper}
  s.description = %q{Fitbit OmniAuth strategy + API wrapper}
  s.license     = "MIT"

  s.files         = Dir["{app,config,db,lib}/**/*"] + ["LICENSE.md", "Rakefile", "README.md"]
  s.executables   = s.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]

  s.add_runtime_dependency 'omniauth-fitbit', '~> 1.0'
end
