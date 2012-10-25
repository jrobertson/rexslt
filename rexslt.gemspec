Gem::Specification.new do |s|
  s.name = 'rexslt'
  s.version = '0.4.00'
  s.summary = 'Rexslt is an XSLT processor written purely in Ruby'
  s.authors = ['James Robertson']
  s.files = Dir['lib/**/*.rb']
  s.add_dependency('rxfhelper')
  s.add_dependency('rexle')
end
