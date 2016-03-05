Gem::Specification.new do |s|
  s.name = 'rexslt'
  s.version = '0.4.3'
  s.summary = 'Rexslt is an XSLT processor written purely in Ruby'
  s.authors = ['James Robertson']
  s.files = Dir['lib/**/*.rb']
  s.add_runtime_dependency('rxfhelper', '~> 0.1', '>=0.1.12')
  s.add_runtime_dependency('rexle', '~> 1.0', '>=1.0.11') 
  s.signing_key = '../privatekeys/rexslt.pem'
  s.cert_chain  = ['gem-public_cert.pem']
  s.license = 'MIT'
  s.email = 'james@r0bertson.co.uk'
  s.homepage = 'https://github.com/jrobertson/rexslt'
  s.required_ruby_version = '>= 2.1.2'
end

