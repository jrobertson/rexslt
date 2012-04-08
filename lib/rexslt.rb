#!/usr/bin/env ruby

# file: rexslt.rb

require 'rexle'
require 'rxfhelper'


class Rexle::Element
  def to_xpath(option=nil)
    def attribute_scan(node)
      result = ''
      attr = %w(id class).detect {|x| node.attributes.has_key? x}
      if attr then
        value = node.attribute[attr]
        result = "[@%s='%s']" % [attr, value]
      end
      result
    end

    def doc_scan(node, option=nil)
      name = node.name
      attribute = option == :no_cond ? '' : attribute_scan(node)
      result = doc_scan(node.parent,option) unless node.root === node.doc_root
      [result, name.to_s + attribute]
    end

    doc_scan(self, option).flatten.compact.join('/')
  end
end


class Rexslt

  def initialize(xsl, xml)    
    super()
    xslt_transform *[xsl, xml].map{|x| RXFHelper.read(x).first}
  end
  
  def to_s() 
    @doc.to_s[/<root>(.*)<\/root>/m,1]
  end
             
  def to_doc(); @doc; end
    
  alias to_xml to_s

  private

  def xsl_apply_templates(element, x, doc_element, indent)
    
    field = x.attributes[:select]
    node = element.element field

    return unless node

    keypath = node.to_xpath :no_cond
    matched_node = nil
    
    # check for a nest <xsl:sort element
       
    sort = x.element('xsl:sort')
    if sort then
      orderx = sort.attributes[:order]
      sort_field = sort.attributes[:select]
    end

    raw_template = @templates.to_a.find do |raw_item, template|

      item = raw_item.split('/')

      if match? keypath, item then
        matched_node = element.xpath field
        true
      else
        child = item.pop
        if item.length > 0 and match? keypath, item then
          matched_node = node.xpath child
          matched_node.any? ? true : false
        end
      end
    end

    if matched_node then
      
      template_xpath, template = raw_template
      
      if sort_field then
        matched_node.sort_by{|x| x.element(sort_field).text}.each do |child_node|       
          read_node template, child_node, doc_element, indent
        end
      else
        matched_node.each do |child_node|      
          read_node template, child_node, doc_element, indent
        end        
      end
    end

  end
  
  def match?(keypath, path)
    x = keypath.split('/').reverse.take path.length
    x == path.reverse
  end
  

  def xsl_attribute(element, x, doc_element, indent)
    
    name = x.attributes[:name]
    value = x.text
    doc_element.add_attribute name, value
  end

  def xsl_choose(element, x, doc_element, indent)

    #get the when clause    

    r = x.xpath("xsl:when").map do |xsl_node|

      condition = xsl_node.attributes[:test]
      node = element.element condition
            
      if node and node == true      
        read_node(xsl_node, element, doc_element, indent)      
        true
      else
        false
      end
    end

    unless r.any? then
      node = x.element 'xsl:otherwise'
      read_node(node, element, doc_element, indent) if node
    end       

  end
  
  def xsl_copy_of(element, x, doc_element, indent)

    indent_element(element, x, doc_element, indent, indent - 1) do
      doc_element.add element 
    end

  end
  
  def xsl_element(element, x, doc_element, indent)

    indent_before(element, x, doc_element, indent + 1) if @indent == true

    name = x.attributes[:name]
    new_element = Rexle::Element.new(name).add_text(x.text)
    doc_element.add new_element
    read_node(x, element, new_element, indent)
    indent_after(element, x, doc_element, indent) if @indent == true
  end
  
  def xsl_for_each(element, x, doc_element, indent)
    
    xpath = x.attributes[:select]
    nodes = element.match xpath
    
    # check for sort
    sort_node = x.element 'xsl:sort'
    
    if sort_node then

      sort_field = sort_node.attributes[:select]
      order = sort_node.attributes[:order]
      sort_node.parent.delete sort_node
      
      nodes = nodes.sort_by do |node|

        r = node.element sort_field
        if r.is_a? Rexle::Element then
          r.text
        else
          # it's a string
          r
        end
      end

      nodes.reverse! if order.downcase == 'descending'
    end
     
    nodes.each {|node| read_node(x, node, doc_element, indent)}
    
  end
    
  def xsl_if(element, x, doc_element, indent)
    
    condition = x.attributes[:test]
    node = element.element, condition
    read_node(x, element, doc_element, indent) if node and node == true
  end

  def indent_before(element, x, doc_element, indent)
    text = ''
    unless doc_element.texts.empty? and doc_element.texts.last.nil? then      
      text = '  ' * (indent - 1)  unless doc_element.texts.last.to_s[/^\n\s/m]
    else
      text = "\n" + '  ' * (indent - 1)
    end
    text = '  ' if text.empty?

    doc_element.add_text text if text
  end

  def indent_after(element, x, doc_element, prev_indent)

    if @indent == true then          
      doc_element.add_text "\n" + '  ' * (prev_indent > 0 ? prev_indent - 1 : prev_indent)
    end            
  end
  
  def indent_element(element, x, doc_element, indent, previous_indent)    
    indent_before(element, x, doc_element, indent) if @indent == true    
    yield
    indent_after(element, x, doc_element, previous_indent) if @indent == true
  end  

  def padding(element,raw_indent, x)    
    # if there is any other elements in doc_element don't check for an indent!!!!

    indent = 0    
    indent = raw_indent + 1  if element.texts.length <= 0     
    x.to_s.strip.length > 0 ? '  ' * indent : ''        
  end
  
  def read_node(template_node, element, doc_element, indent)

    procs = {"Rexle::Element" => :read_raw_element, "String" => :read_raw_text}        

    template_node.each do |x|
      method(procs[x.class.to_s]).call(element, x, doc_element, indent)
    end
  end

  # element: xml source element, x: xsl element, doc_element: current destination xml element
  #
  def read_raw_text(element, x, doc_element, raw_indent)
    #val = @indent == true ? padding(doc_element, raw_indent, x) : ''
    if x.to_s.strip.length > 0 then
      val = x.to_s #
      doc_element.add_element val
    end
  end
  
  def read_raw_element(element, x, doc_element, indent)
    
    method_name = x.name.gsub(/[:-]/,'_').to_sym
    
    if @xsl_methods.include? method_name then
      method(method_name).call(element, x, doc_element, indent)
    else
      
      previous_indent = indent        
      la = x.name

      if x.children.length > 0 then           

        new_indent = indent + 1        
        new_element = x.clone

        new_element2 = new_element.deep_clone
        new_element2.attributes.each do |k,v|
          
          if v[/{/] then

            v.gsub!(/(\{[^\}]+\})/) do |x2|
              element.text(x2[/\{([^\}]+)\}/,1]).clone
            end

          end  
        end

        indent_before(element, x, doc_element, new_indent) if @indent == true

        #jr070412 new_element.text = new_element.text.strip if @indent == false
        doc_element.add new_element2

        read_node(x, element, new_element2, new_indent)        
        indent_after(element, x, doc_element, previous_indent) if @indent == true

      else

        unless doc_element.children.length > 0
          indent_before(element, x, doc_element, indent) if @indent == true
        end
        
        val = @indent == true ? '  ' + x.to_s : x.to_s        
        doc_element.add val

        if @indent == true then
          indent_after(element, x, doc_element, previous_indent)
        end

      end
    end    
  end

  def xsl_text(element, x, doc_element, indent)
    val = @indent == true ? padding(doc_element, indent, x) : ''
    val += x.text
    doc_element.add_element val
  end
  
  def xsl_value_of(element, x, doc_element, indent)

    field = x.attributes[:select]
    o = field == '.' ? element.text : element.text(field)   
    doc_element.add_element o.to_s
  end  

  def xslt_transform(xsl, xml)
   
    doc_xml = Rexle.new xml
    @doc_xsl = Rexle.new xsl

    @doc = Rexle.new '<root/>'
    indent = 0

    previous_indent = 0
    @xsl_methods = [:'xsl_apply_templates', :'xsl_value_of', :'xsl_element', :'xsl_if', :'xsl_choose', 
                    :'xsl_when', :'xsl_copy_of', :'xsl_attribute', :'xsl_for_each', :'xsl_text']
    
    strip_space = @doc_xsl.root.element "xsl:strip-space/attribute::elements"

    if strip_space then
      elements = strip_space.value
      elements.split.each do |element|
        nodes = doc_xml.root.xpath "//" + element + "[text()]"
        a = nodes.select {|x| x.text.to_s.strip.empty?}
        a.each {|node| node.parent.delete node}
      end      
    end

    h = @doc_xsl.root.xpath("xsl:output/attribute::*").inject({})\
      {|r,x| r.merge(x.name.to_sym => x.value)}

    @indent = (h and h[:indent] == 'yes') ? true : false

    # fetch the templates
    #puts "Rexle:Version: " + Rexle.version
    
    @templates = @doc_xsl.root.xpath('xsl:template').inject({}) do |r,x|
      r.merge(x.attributes[:match] || x.attributes[:select] => x)
    end

    # using the 1st template    
    xpath = String.new @templates.to_a[0][0] 

    if doc_xml.root.name == xpath then
      read_node(@templates.to_a[0][-1], doc_xml.element(xpath), @doc.root, indent) 
    else
      # use this template
      node = doc_xml.root.element(xpath)      
      read_node(@templates.to_a[0][-1], doc_xml, node, indent) 
    end
    
  end

end