require 'rexml/document'


class Rexslt
  include REXML
  
  def initialize(xsl, xml)
   
    doc_xml = Document.new(xml)
    doc_xsl = Document.new(xsl)
    
    @doc = Document.new('<root/>')
    indent = ''
    previous_indent = indent.clone
    @xsl_methods = [:apply_templates, :value_of, :element, :if, :choose, :when, :copy_of, :attribute]

    h = XPath.match(doc_xsl.root, "xsl:output/attribute::*").inject({})\
      {|r,x| r.merge(x.name.to_sym => x.value)}

    @indent = true if h and h[:indent] == 'yes'

    # fetch the templates
    @templates = XPath.match(doc_xsl.root, 'xsl:template').inject({}) do |r,x|
      r.merge(x.attribute('match').value => x)
    end

    # using the 1st template
    xpath = String.new @templates.to_a[0][0] 
    XPath.match(doc_xml, xpath).each_with_index do |x,i|
      read_node @templates.to_a[0][-1], x, @doc.root, indent.clone, previous_indent.clone
    end
  end

  def to_s() 
    @doc.to_s[/<root>(.*)<\/root>/m,1]
  end
             
  def to_doc(); @doc; end

  private

  def read_node(template_node, element, doc_element, indent, previous_indent)

    procs = {"REXML::Element" => :read_raw_element, "REXML::Text" => :read_raw_text}
    template_node.each do |x|
      method(procs[x.class.to_s]).call(element, x, doc_element, indent.clone, previous_indent)
    end

  end

  # element: xml source element, x: xsl element, doc_element: current destination xml element
  #
  def read_raw_text(element, x, doc_element, raw_indent, previous_indent)

    indent = @indent == true ? (raw_indent + '  ') : ''
    doc_element.add(REXML::Text.new(indent + x.to_s, raw=true)) if x.to_s.strip.length > 0 
  end
  
  def read_raw_element(element, x, doc_element, indent, previous_indent)
    
    method_name = x.name.gsub(/-/,'_').to_sym
    if @xsl_methods.include? method_name then

      method(method_name).call(element, x, doc_element, indent, previous_indent)
    else

      if x.has_elements? then           
        
        new_element = Element.new x.name.to_s

        previous_indent = indent.clone
        indent = indent_before(element, x, doc_element, indent, previous_indent) if @indent == true
        
        doc_element.add new_element
        read_node(x, element, new_element, indent.clone, previous_indent.clone)
        
        indent_after(element, x, doc_element, indent, previous_indent) if @indent == true

      else
        doc_element.add Document.new(x.to_s)

      end
    end    
  end

  def apply_templates(element, x, doc_element, indent, previous_indent)
    
    field = x.attribute('select').value.to_s
    XPath.match(element, field).each do |x|
      read_node @templates[field], x, doc_element, indent, previous_indent
    end
  end

  def value_of(element, x, doc_element, indent, previous_indent)
    
    field = x.attribute('select').value.to_s
    o = element.text(field)
    doc_element.add REXML::Text.new(o.to_s)

  end

  def element(element, x, doc_element, indent, previous_indent)

    name = x.attribute('name').value.to_s    
    new_element = Element.new name
    doc_element.add new_element
    read_node(x, element, new_element, indent, previous_indent)
  end
  
  def if(element, x, doc_element, indent, previous_indent)
    
    condition = x.attribute('test').value.to_s
    node = XPath.first(element, condition)
    read_node(x, element, doc_element, indent, previous_indent) if node and node == true
  end

  def choose(element, x, doc_element, indent, previous_indent)

    #get the when clause    

    r = XPath.match(x, "xsl:when").map do |xsl_node|
      condition = xsl_node.attribute('test').value.to_s
      node = XPath.first(element, condition)
      if node and node == true
        read_node(xsl_node, element, doc_element, indent, previous_indent)      
        true
      else
        false
      end
    end

    unless r.any? then
      node = XPath.first(x, 'xsl:otherwise')
      read_node(node, element, doc_element, indent, previous_indent) if node
    end       

  end
  
  def copy_of(element, x, doc_element, indent, previous_indent)

    indent_element(element, x, doc_element, indent, previous_indent) do
      doc_element.add element 
    end

  end
  
  def indent_before(element, x, doc_element, indent, previous_indent)
    text = ''
    unless doc_element.texts.empty? and doc_element.texts.last.nil? then
      text = indent unless doc_element.texts.last.to_s[/^\n\s/m]
    else
      text = "\n" + indent
    end
    (doc_element.add REXML::Text.new text, raw=true) if text
    indent += '  '    
  end

  def indent_after(element, x, doc_element, indent, previous_indent)
    if @indent == true then          
      doc_element.add REXML::Text.new "\n" + previous_indent[0..-3], raw=true
    end            
  end
  
  def indent_element(element, x, doc_element, indent, previous_indent)    
    indent_before(element, x, doc_element, indent, previous_indent) if @indent == true    
    yield
    indent_after(element, x, doc_element, indent, previous_indent) if @indent == true
  end
  
  def attribute(element, x, doc_element, indent, previous_indent)
    
    name = x.attribute('name').value
    value = x.text.to_s
    doc_element.add_attribute name, value
  end
  
end