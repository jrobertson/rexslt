Gem::Specification.new do |s|
  s.name = 'rexslt'
  s.version = '0.6.13'
  s.summary = 'Rexslt is an XSLT processor written purely in Ruby'
  s.authors = ['James Robertson']
  s.files = Dir['lib/rexslt.rb']
  s.add_runtime_dependency('rxfhelper', '~> 0.4', '>=0.4.3')
  s.add_runtime_dependency('rexle', '~> 1.4', '>=1.4.12') 
  s.signing_key = '../privatekeys/rexslt.pem'
  s.cert_chain  = ['gem-public_cert.pem']
  s.license = 'MIT'
  s.email = 'james@jamesrobertson.eu'
  s.homepage = 'https://github.com/jrobertson/rexslt'
  s.required_ruby_version = '>= 2.1.2'
end

