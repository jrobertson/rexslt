#!/usr/bin/env ruby

# file: rexslt.rb
 
require 'rexml/document'

class Rexslt
  include REXML

  def initialize(xsl, xml)

    doc_xml = Document.new(xml)
    doc_xsl = Document.new(xsl)

    # fetch the templates
    @templates = XPath.match(doc_xsl.root, 'xsl:template').inject({}) do |r,x|
      r.merge(x.attribute('match').value => x)
    end

    # using the 1st template
    @a = XPath.match(doc_xml, @templates.to_a[0][0]).map do |x|
      read_template @templates.to_a[0][-1], x
    end

  end

  def to_s()
    @a.flatten.join    
  end

  alias text to_s

  private

  def read_template(template_node, doc_node)

    XPath.match(template_node, '*').map do |x|
      method_name = x.name.gsub(/-/,'_').to_sym
      field = x.attribute('select').value.to_s
      method(method_name).call(doc_node, field)
    end
  end

  def apply_templates(doc_node, field)
    XPath.match(doc_node, field).map do |x|
      read_template @templates[field], x
    end
  end

  def value_of(doc_node, field)
    doc_node.text(field)
  end

end
