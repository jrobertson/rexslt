require 'rexml/document'

class Rexslt
  include REXML

  def initialize(xsl, xml)

    doc_xml = Document.new(xml)
    doc_xsl = Document.new(xsl)

    @xsl_methods = [:apply_templates, :value_of, :element, :if, :choose, :when]

    # fetch the templates
    @templates = XPath.match(doc_xsl.root, 'xsl:template').inject({}) do |r,x|
      r.merge(x.attribute('match').value => x)
    end

    xpath = String.new @templates.to_a[0][0] 
    o = XPath.first(doc_xml, xpath)

    # using the 1st template
    @a = XPath.match(doc_xml, xpath).map do |x|
      read_node @templates.to_a[0][-1], x
    end

  end

  def to_s() @a.flatten.join end

  def to_a() @a end

  alias text to_s

  private

  def read_node(template_node, doc_node)

    procs = {"REXML::Element" => :read_raw_element, "REXML::Text" => :read_raw_text}
    template_node.map do |x|
      #puts 'x : ' + x.inspect
      method(procs[x.class.to_s]).call(doc_node, x)
    end
    
  end

  def read_raw_text(doc_node, x)
    r = x.to_s.strip.length > 0 ? x.to_s : ''
    #puts 'xx : ' + r.inspect
    r
  end
  
  def read_raw_element(doc_node, x)
    method_name = x.name.gsub(/-/,'_').to_sym
    if @xsl_methods.include? method_name then

      method(method_name).call(doc_node, x)
    else

      if x.has_elements? then           
        element = "<%s>%%s</%s>" % ([x.name.to_s] * 2)
        k = element % read_node(x, doc_node).flatten.join
        #puts 'k : ' + k.inspect
        k
      else        
        x.to_s
      end
    end    
  end

  def apply_templates(doc_node, x)
    field = x.attribute('select').value.to_s
    XPath.match(doc_node, field).map do |x|
      read_node @templates[field], x
    end
  end

  def value_of(doc_node, x)
    field = x.attribute('select').value.to_s
    doc_node.text(field)
  end

  def element(doc_node, x)
    name = x.attribute('name').value.to_s
    element = "<%s>%%s</%s>" % ([name] * 2)
    r = element % (read_node(x, doc_node).flatten.join)
    #puts 'r : ' + r.inspect
    r
  end
  
  def if(doc_node, x)
    condition = x.attribute('test').value.to_s
    node = XPath.first(doc_node, condition)
    read_node(x, doc_node).flatten.join if node and node == true
  end

  def choose(doc_node, x)

    #get the when clause    
    nodes = XPath.match(x, "xsl:when")

    r = nodes.map do |xsl_node|

      condition = xsl_node.attribute('test').value.to_s
      node = XPath.first(doc_node, condition)

      if node and node == true then
        read_node(xsl_node, doc_node).flatten.join       
      else
        nil
      end
    end

    if r.compact.length <= 0 then
      xsl_node = XPath.first(x, 'xsl:otherwise')
      r = read_node(xsl_node, doc_node).flatten.join if xsl_node
    end
    
    r
  end
end
