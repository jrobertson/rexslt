#!/usr/bin/env ruby

# file: rexslt.rb

require 'rexle'
require 'rxfhelper'


module RexPath
  
  refine Rexle::Element do
    
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
end


class Rexslt
  using RexPath
  
  def initialize(xsl, xml, params={})    
    
    ## debugging variables
    
    @rn = 0
    @rre = 0

    super()
    @options = {}
    custom_params = params.inject({}){|r,x| r.merge(Hash[x[0].to_s,x[1]])}    

    xslt_transform(*[xsl, xml].map{|x| RXFHelper.read(x).first}, custom_params)
  end
  
  def to_s(options={})
    @doc.to_s(@options.merge(options)).sub('<root>','').sub(/<\/root>$/m,'')
  end
             
  def to_doc(); @doc; end
    
  alias to_xml to_s

  private
  
  def filter_out_spaces(e)

    e.children.each do |x|

      if x.is_a? String and e.name != 'xsl:text' then

        x.gsub!(/\n/,'')
        x.gsub!(/ +/,'')

      elsif x.is_a? Rexle::Element and x.children.length > 0 then
        filter_out_spaces x
      end
      
    end
  end
  

  def xsl_apply_templates(element, x, doc_element, indent, i)

    field = x.attributes[:select]
    node = element.element field
    return unless node

    keypath = node.to_xpath :no_cond
    matched_node = nil
    
    # check for a nest <xsl:sort element
       
    sort = x.element('xsl:sort')
    
    if sort then

      orderx = sort.attributes[:order] || 'ascending'
      sort_field = sort.attributes[:select]
      data_type = sort.attributes[:'data-type'] || 'text'

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
                
        sort_order = lambda do |x| 
          
          r = x.element(sort_field); 

          if r.respond_to?(:text) then 
            r.value
          else
            data_type == 'text' ? r : r.to_i
          end
        end

        a = matched_node.sort_by(&sort_order).each_with_index do |child_node,i| 
          read_node template, child_node, doc_element, indent, i+1
        end
        a.reverse! if orderx == 'descending'
      else
        r = matched_node.each_with_index do |child_node,i|      
          read_node template, child_node, doc_element, indent, i+1
        end        
        return r
      end
    end

  end
  
  def match?(raw_keypath, raw_path)
    return false if raw_path == ['*']
    keypath = raw_keypath.split('/').reverse.take raw_path.length    
    path = raw_path.reverse
    r = path.map.with_index.select{|x,i|x == '*'}.map(&:last)

    r.each do |n|  
      # get the relative value from path
      path[n] = keypath[n]
    end    
    
    keypath == path    
  end
  
  def position()
    @position ||= 0
  end

  def xsl_attribute(element, x, doc_element, indent, i)

    name = x.attributes[:name]
    value = x.value

    e = x.element('xsl:value-of')
    value = value_of(e, element) if e
    doc_element.add_attribute(name, value)
  end

  def xsl_choose(element, x, doc_element, indent, i)
    
    r = x.xpath("xsl:when").map do |xsl_node|

      condition = xsl_node.attributes[:test]
      node = element.element condition
      
      if node and node == true      
        read_node(xsl_node, element, doc_element, indent, i)      
        true
      else
        false
      end
    end
    
    unless r.any? then
      otherwise = x.element("xsl:otherwise")
      if otherwise then
        read_node(otherwise, element, doc_element, indent)
      end
    end       

  end
  
  def xsl_copy_of(element, x, doc_element, indent, i)
    #jr251012 indent = 1 unless indent
    #jr251012 indent_element(element, x, doc_element, indent, indent - 1) do
      field = x.attributes[:select]
      element.xpath(field).each do |child|
        doc_element.add child
      end
    #jr251012 end

  end
  
  def xsl_element(element, x, doc_element, indent, i)

    indent_before(element, x, doc_element, indent + 1, i) if @indent == true

    name = x.attributes[:name]
    variable = name[/^\{(.*)\}$/,1]

    if variable then
      name = element.element(variable)
    end

    new_element = Rexle::Element.new(name) # .add_text(x.value.strip)
    #jr060416 doc_element.text = element.text if element.text
    new_element.text = element.text if element.text

    read_node(x, element, new_element, indent, i)
    doc_element.add new_element    
    indent_after(element, x, doc_element, indent) if @indent == true
  end
  
  def xsl_for_each(element, x, doc_element, indent, i)
    
    xpath = x.attributes[:select]

    nodes = element.xpath xpath
    
    # check for sort
    sort_node = x.element 'xsl:sort'
    
    if sort_node then

      sort_field = sort_node.attributes[:select]
      raw_order = sort_node.attributes[:order]
      sort_node.parent.delete sort_node

      if sort_field then
        nodes = nodes.sort_by do |node|

          r = node.element sort_field

          if r.is_a? Rexle::Element then
            r.value
          else
            # it's a string
            r
          end
        end

      end
      
      field = raw_order[/^\{\$(.*)\}/,1]
      order =  field ?  @param[field] : raw_order
      nodes.reverse! if order.downcase == 'descending'
    end
     
    nodes.each {|node| read_node(x, node, doc_element, indent, i)}
    
  end
    
  def xsl_if(element, x, doc_element, indent, i=0)

    condition = x.attributes[:test].clone
    
    cond = condition.slice!(/position\(\) &lt; \d+/)
    
    result = if cond then
      
      cond.sub!(/position\(\)/, i.to_s)
      cond.sub!(/&lt;/,'<')
      cond.sub!(/&gt;/,'>')

      b = eval(cond)

      if b then

        if condition.length > 0 then
          element.element condition   
        else
          true
        end
      else
        false
      end
            
    else

      element.element condition
    end

    if result then
      read_node x, element,  doc_element, indent, i
    end

  end
  
  # Ignores comment tags
  #
  def ignore(*args)
  end

  def indent_before(element, x, doc_element, indent, i)
    text = ''
    unless doc_element.texts.empty? and doc_element.texts.last.nil? then      
      if indent > 1 then
        text = "\n" + '  ' * (indent - 1)  #unless doc_element.texts.last.to_s[/^\n\s/m]
      end
    else
      text = "\n" + '  ' * (indent - 1)
    end

    doc_element.add_text text if text
  end

  def indent_after(element, x, doc_element, prev_indent)

    if @indent == true then          
      doc_element.add_text "\n" + '  ' * (prev_indent > 0 ? prev_indent - 1 : prev_indent)
    end            
  end
  
  def indent_element(element, x, doc_element, indent, previous_indent)    
    indent_before(element, x, doc_element, indent, i) if @indent == true    
    yield
    indent_after(element, x, doc_element, previous_indent) if @indent == true
  end  

  def padding(element,raw_indent, x)    
    # if there is any other elements in doc_element don't check for an indent!!!!

    indent = 0    
    indent = raw_indent + 1  if element.texts.length <= 0     
    x.to_s.strip.length > 0 ? '  ' * indent : ''        
  end
  
  
  # Reads an XSL node which is either an XSL element, a string or a comment
  # template_node: XSL node
  # element: XML node
  # doc_element: target document element
  #
  def read_node(template_node, element, doc_element, indent, i=0)
        
    procs = {
      "Rexle::Element" => :read_raw_element, 
      "String" => :read_raw_text, 
      "Rexle::Comment" => :ignore
    }

    template_node.children.each_with_index do |x,j|
      
      # x: an XSL element, or a string or a comment
      method(procs[x.class.to_s]).call(element, x, doc_element, indent, i)
    end

  end

  # element: xml source element, x: xsl element, doc_element: current destination xml element
  #
  def read_raw_text(element, x, doc_element, raw_indent, i)

    #val = @indent == true ? padding(doc_element, raw_indent, x) : ''
    if x.to_s.strip.length > 0 then

      val = x.to_s #
      doc_element.add_element val
    end

    #doc_element.add_text x if x.is_a? String

  end
  
  # element: xml element
  # x: xsl element
  # doc_element: 
  #
  def read_raw_element(element, x, doc_element, indent, j)
    
    method_name = x.name.gsub(/[:-]/,'_').to_sym    

    if @xsl_methods.include? method_name then

      if method_name == :'xsl_apply_templates' then
        #doc_element = doc_element.elements.last
      end

      method(method_name).call(element, x, doc_element, indent, j)

    else

      previous_indent = indent      
      la = x.name
      new_indent = indent + 1  if @indent == true

      new_element = x.clone

      new_element.attributes.each do |k,raw_v|

        v = raw_v.is_a?(Array) ? raw_v.join(' ') : raw_v
                  
        if v[/{/] then

          v.gsub!(/(\{[^\}]+\})/) do |x2|

            xpath = x2[/\{([^\}]+)\}/,1]
            text = element.text(xpath)
            text ? text.clone : ''
            
          end

        end  
      end      
            
      if x.children.length > 0 then           

        indent_before(element, x, doc_element, new_indent, j) if @indent == true
             
        read_node(x, element, new_element, new_indent, j)        
        doc_element.add new_element   

        if @indent == true then
          if doc_element.children.last.children.any? \
              {|x| x.is_a? Rexle::Element} then

            doc_element.children.last.add_text "\n" + '  ' * (new_indent - 1)
          end
        end


      else

        indent_before(element, x, doc_element, new_indent, j) if @indent == true
        
        val = @indent == true ? x.to_s : x.to_s        
        doc_element.add val

      end
            
    end
    
  end
  
  def value_of(x, element)
    
    field = x.attributes[:select]

    o = case field
      when '.'
        element.value
      when /^\$/
        @param[field[/^\$(.*)/,1]]
    else
      ee = element.text(field) 
      ee
    end
    
  end
  
  def xsl_output()

  end
  
  def xsl_text(element, x, doc_element, indent, i)

    val = @indent == true ? padding(doc_element, indent, x) : ''    
    
    val += if x.attributes[:"disable-output-escaping"] then
      x.value.unescape
    else
      x.value.to_s
    end
    
    doc_element.add_element val
    
  end
  
  def xsl_value_of(element, x, doc_element, indent, i)
    
    s = value_of(x, element)

    #jr030316 doc_element.add_element o.to_s #unless o.to_s.empty?

    doc_element.add_text  s
    
    doc_element
  end
  

  def xslt_transform(raw_xsl, xml, custom_params={})

    doc_xml = xml.is_a?(Rexle) ? xml : Rexle.new(xml)
 
    @doc_xsl = raw_xsl.is_a?(Rexle) ? raw_xsl : Rexle.new(raw_xsl)
    
    
    filter_out_spaces @doc_xsl.root

    @doc = Rexle.new '<root></root>'
    indent = 0

    previous_indent = 0
    @xsl_methods = %i(apply_templates value_of element if choose when copy_of
                      attribute for_each text output).map do |x| 
                        ('xsl_' + x.to_s).to_sym
                      end
    
    strip_space = @doc_xsl.root.element "xsl:strip-space/attribute::elements"

    if strip_space then
      elements = strip_space.value
      elements.split.each do |element|
        nodes = doc_xml.root.xpath "//" + element + "[text()]"
        a = nodes.select {|x| x.value.to_s.strip.empty?}
        a.each {|node| node.parent.delete node}
      end      
    end

    h = @doc_xsl.root.element("xsl:output/attribute::*")
    
    if  h and ((h[:method] and h[:method].downcase == 'html') \
                                   or h[:'omit-xml-declaration'] == 'yes') then
      @options[:declaration] = :none 
    end

    @indent =  (h and h[:indent] == 'yes') ? true : false
    
    params = @doc_xsl.root.xpath("xsl:param").map{|x| [x.attributes[:name], x.value]}
    @param = Hash[params].merge(custom_params) if params
    # search for params
    
    
    # fetch the templates
    #puts "Rexle:Version: " + Rexle.version
    
    @templates = @doc_xsl.root.xpath('xsl:template').inject({}) do |r,x|
      r.merge(x.attributes[:match] || x.attributes[:select] => x)
    end

    # using the 1st template    
    xpath = String.new @templates.to_a[0][0]
    out = read_node(@templates.to_a[0][-1], doc_xml.element(xpath), @doc.root, indent)
    

    if @doc_xsl.root.element('xsl:output[@method="html"]') then
      
      head = @doc.root.element('html/head')

      if head and not head.element('meta[@content]') then
        
        h = {
          :'http-equiv' => "Content-Type", 
          content: 'text/html; charset=utf-8'
        }
        meta_element = Rexle::Element.new('meta', attributes: h)
        child = head.element('*')
        
        if child then
          child.insert_before meta_element
        else
          head.add meta_element
        end

      end
    end    

    out

  end

end