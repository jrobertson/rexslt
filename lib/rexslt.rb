require 'rexml/document'

class Rexslt
  include REXML

  def initialize(xsl, xml)

    doc_xml = Document.new(xml)
    doc_xsl = Document.new(xsl)

    @xsl_methods = [:apply_templates, :value_of]

    # fetch the templates
    @templates = XPath.match(doc_xsl.root, 'xsl:template').inject({}) do |r,x|
      r.merge(x.attribute('match').value => x)
    end

    # using the 1st template
    @a = XPath.match(doc_xml, @templates.to_a[0][0]).map do |x|
      read_template @templates.to_a[0][-1], x
    end

  end

  def to_s() @a.flatten.join end

  def to_a() @a end

  alias text to_s

  private

  def read_template(template_node, doc_node)

    XPath.match(template_node, '*').map do |x|      

      method_name = x.name.gsub(/-/,'_').to_sym

      if @xsl_methods.include? method_name then
        field = x.attribute('select').value.to_s if x.attribute('select')
        method(method_name).call(doc_node, field)
      else
        x.to_s
      end
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
