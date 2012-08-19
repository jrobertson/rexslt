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

  def initialize(xsl, xml, params={})    
    super()
    custom_params = params.inject({}){|r,x| r.merge(Hash[x[0].to_s,x[1]])}    
    xslt_transform(*[xsl, xml].map{|x| RXFHelper.read(x).first}, custom_params)
  end
  
  def to_s(options={}) 
    @doc.to_s(options)[/<root>(.*)<\/root>/m,1]
  end
             
  def to_doc(); @doc; end
    
  alias to_xml to_s

  private

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
            orderx == 'ascending' ? r.value : -r.value
          else
            
            if orderx == 'ascending' then
              data_type == 'text' ? r : r.to_i
            else
              data_type == 'text' ? -r : -r.to_i
            end
          end
        end

        matched_node.sort_by(&sort_order).each_with_index do |child_node,i| 
          read_node template, child_node, doc_element, indent, i+1
        end
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
    doc_element.add_attribute name, value
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
      node = x.element 'xsl:otherwise'
      read_node(node, element, doc_element, indent) if node
    end       

  end
  
  def xsl_copy_of(element, x, doc_element, indent, i)
    indent = 1 unless indent
    indent_element(element, x, doc_element, indent, indent - 1) do
      field = x.attributes[:select]
      child = element.element(field)
      doc_element.add child
    end

  end
  
  def xsl_element(element, x, doc_element, indent, i)

    indent_before(element, x, doc_element, indent + 1, i) if @indent == true
    name = x.attributes[:name]
    variable = name[/^\{(.*)\}$/,1] 
    if variable then
      name = element.element("name()")
    end

    new_element = Rexle::Element.new(name).add_text(x.value.strip)
    doc_element.add new_element
    read_node(x, element, new_element, indent, i)
    indent_after(element, x, doc_element, indent, i) if @indent == true
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
    
    condition = x.attributes[:test].gsub('position()',i.to_s).gsub('&lt;','<').gsub('&gt;','>')
    result = element.element condition

    if result then

      read_node x.children, x,  doc_element, indent, i
    end

  end

  def indent_before(element, x, doc_element, indent, i)
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
    indent_before(element, x, doc_element, indent, i) if @indent == true    
    yield
    indent_after(element, x, doc_element, previous_indent, i) if @indent == true
  end  

  def padding(element,raw_indent, x)    
    # if there is any other elements in doc_element don't check for an indent!!!!

    indent = 0    
    indent = raw_indent + 1  if element.texts.length <= 0     
    x.to_s.strip.length > 0 ? '  ' * indent : ''        
  end
  
  def read_node(template_node, element, doc_element, indent, i=0)

    procs = {"Rexle::Element" => :read_raw_element, "String" => :read_raw_text}        

    template_node.each do |x|
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
  end
  
  def read_raw_element(element, x, doc_element, indent, i)

    method_name = x.name.gsub(/[:-]/,'_').to_sym

    if @xsl_methods.include? method_name then
      if method_name == :'xsl_apply_templates' then
        #doc_element = doc_element.elements.last
      end
      method(method_name).call(element, x, doc_element, indent, i)
    else
      
      previous_indent = indent      
      la = x.name

      if x.children.length > 0 then           

        new_indent = indent + 1        if @indent == true
        new_element = x.clone

        new_element2 = new_element.deep_clone
        new_element2.attributes.each do |k,v|
          
          if v[/{/] then

            v.gsub!(/(\{[^\}]+\})/) do |x2|
              element.value(x2[/\{([^\}]+)\}/,1]).clone
            end

          end  
        end

        indent_before(element, x, doc_element, new_indent, i) if @indent == true

        new_element2.value = new_element2.value.strip
        doc_element.add new_element2

        read_node(x, element, new_element2, new_indent, i)        
        indent_after(element, x, doc_element, previous_indent, i) if @indent == true

      else

        unless doc_element.children.length > 0
          indent_before(element, x, doc_element, indent, i) if @indent == true
        end
        
        val = @indent == true ? '  ' + x.to_s : x.to_s        
        doc_element.add val

        if @indent == true then
          indent_after(element, x, doc_element, previous_indent, i)
        end

      end
    end    
  end
  
  def xsl_text(element, x, doc_element, indent, i)
    val = @indent == true ? padding(doc_element, indent, x) : ''    
    val += x.value
    doc_element.add_element val
  end
  
  def xsl_value_of(element, x, doc_element, indent, i)

    field = x.attributes[:select]
    o = case field
      when '.'
        element.value
      when /^\$/
        @param[field[/^\$(.*)/,1]]
    else
      element.value(field)           
    end

    doc_element.add_element o.to_s
  end  

  def xslt_transform(xsl, xml, custom_params={})
   
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
        a = nodes.select {|x| x.value.to_s.strip.empty?}
        a.each {|node| node.parent.delete node}
      end      
    end

    h = @doc_xsl.root.xpath("xsl:output/attribute::*").inject({})\
      {|r,x| r.merge(x.name.to_sym => x.value)}

    @indent = (h and h[:indent] == 'yes') ? true : false

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
    read_node(@templates.to_a[0][-1], doc_xml.element(xpath), @doc.root, indent) 
    
  end

end