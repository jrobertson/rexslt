Gem::Specification.new do |s|
  s.name = 'rexslt'
  s.version = '0.5.6'
  s.summary = 'Rexslt is an XSLT processor written purely in Ruby'
  s.authors = ['James Robertson']
  s.files = Dir['lib/rexslt.rb']
  s.add_runtime_dependency('rxfhelper', '~> 0.2', '>=0.2.3')
  s.add_runtime_dependency('rexle', '~> 1.3', '>=1.3.15') 
  s.signing_key = '../privatekeys/rexslt.pem'
  s.cert_chain  = ['gem-public_cert.pem']
  s.license = 'MIT'
  s.email = 'james@r0bertson.co.uk'
  s.homepage = 'https://github.com/jrobertson/rexslt'
  s.required_ruby_version = '>= 2.1.2'
end

