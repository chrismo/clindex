Gem::Specification.new do |s|
  s.name        = "clindex"
  s.version     = "1.2.1"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["chrismo"]
  s.email       = ["chrismo@clabs.org"]
  s.homepage    = "https://github.com/chrismo/clindex"
  s.summary     = "cLabs Index"
  s.description = "A generic index DRb server. The core index is a hash, each key is an individual term, each value is an array of references for that term. Searches the index with a simple regexp grep against the hash keys to return a single array of all references on matching terms. Multi-user ready via a simple locking mechanism that probably doesn't scale too well. BSD License."

  s.add_dependency('clutil', '>= 2011.138.0')

  s.required_ruby_version = ">=1.8.4"
  s.required_rubygems_version = ">= 1.0.0"

  s.files        = Dir.glob("src/index.rb")
  s.executables  = []
  s.require_path = 'src'
end
