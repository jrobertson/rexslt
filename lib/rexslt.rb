#!/usr/bin/env ruby

# file: rexslt.rb

require 'rexle'
require 'rxfreader'
require 'logger'


# modifications:
#
# 22-Feb-2022: minor improvement: Replaced RXFHelper with RXFReader.
# 01-Feb-2019: bug fix: new line characters are no longer stripped
#                       between XSL elements
#              bug fix: An attribute variable value is now returned correctly
# 19-Jan-2018: feature: Implemented Rexslt#to_xml which returns pretty XML
# 16-Sep-2017: improvement: all predicates in an xsl:choose
#                           condition now must be true
# 15-Sep-2017: feature: Implemented xsl_call_template
# 21-May-2016: bug fix: An update to the Rexle gem regarding the new
#              Rexle::Element::Attribute datatype caused the sort_by code
#              to break. This has now been rectified.
# 04-May-2016: bug fix: disabled the method which strips out all new
#              line spaces, and replaced it with a statement in the
#              read_raw_text() method which strips out space before and
#              after the text
# 03-May-2016: A returned HTML document will no longer include an
#              XML declaration by default
# 30-Apr-2016: bug fix: This class can now be executed within an
#                       eval statement which runs within another class
# 24-Apr-2016: The position() function is now supported within an
#              xsl:value-of select attribute
#              An xsl:attribute value can now be rendered using
#              an xsl:text element

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
  using ColouredText

  def initialize(xsl, xml, raw_params={}, debug: false)

    ## debugging variables

    @rn = 0
    @rre = 0

    super()
    puts 'before options'.info if @debug
    @options = {}

    params = raw_params.merge({debug: false})
    @debug = debug
    custom_params = params.inject({}){|r,x| r.merge(Hash[x[0].to_s,x[1]])}
    puts 'before xsl_transform'.info if @debug

    xslt_transform(*[xsl, xml].map{|x| RXFReader.read(x).first}, custom_params)
  end

  def to_s(options={})
    @doc.to_s(@options.merge(options)).sub(/<root4>/,'').sub(/<\/root4>$/m,'').lstrip
  end

  def to_doc(); @doc; end

  def to_xml()
    @doc.root.xml(pretty: true).sub(/<root4>/,'').sub(/<\/root4>$/m,'')
  end

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
      next unless raw_item
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

          if r.respond_to?(:value) then
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
    value = value_of(e, element, i) if e

    av = x.element('xsl:text')
    if av then
      value = av.text
    end

    doc_element.add_attribute(name, value)
  end

  def xsl_call_template(element, x, doc_element, indent, i)

    name = x.attributes[:name]
    template = @doc_xsl.root.element("xsl:template[@name='#{name}']")

    read_node template, element, doc_element, indent, i
  end

  def xsl_choose(element, x, doc_element, indent, i)


    r = x.xpath("xsl:when").map do |xsl_node|

      condition = xsl_node.attributes[:test]

      if element.xpath(condition).all? then
        read_raw_element(element, xsl_node.elements.first,  doc_element, indent, i)
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

  def xsl_cdata(element, x, doc_element, indent, i)
    puts ('cdata x: ' + element.inspect) if @debug

    new_element = Rexle::CData.new(x.value.to_s)

    read_node(x, element, new_element, indent, i)
    doc_element.add new_element
  end

  def xsl_comment(element, x, doc_element, indent, i)
    #puts ('comment x: ' + element.inspect) if @debug

    new_element = Rexle::Comment.new(x.value.to_s)

    read_node(x, element, new_element, indent, i)
    doc_element.add new_element
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

    puts 'variable: ' + variable.inspect if @debug

    if variable then
      name = element.element(variable)
    end

    new_element = Rexle::Element.new(name) # .add_text(x.value.strip)
    puts 'element.text: ' + element.to_s.inspect if @debug
    new_element.text = element.text.to_s.strip

    read_node(x, element, new_element, indent, i)
    doc_element.add new_element
    indent_after(element, x, doc_element, indent) if @indent == true
  end

  def xsl_for_each(element, x, doc_element, indent, i)

    puts ('inside xsl_for_each x.children: ' + x.children.inspect).debug if @debug
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

          if r.is_a? Rexle::Element or r.is_a? Rexle::Element::Attribute then
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
    puts ('nodes: ' + nodes.inspect).debug if @debug
    nodes.each.with_index {|node, j| read_node(x, node, doc_element, indent, j+1)}

  end

  def xsl_if(element, x, doc_element, indent, i=0)

    cond = x.attributes[:test].clone
    puts ('cond: ' + cond.inspect).debug if @debug

    cond.sub!(/position\(\)/, i.to_s)
    cond.sub!(/&lt;/,'<')
    cond.sub!(/&gt;/,'>')
    cond.sub!(/\bmod\b/,'%')
    cond.gsub!(/&apos;/,"'")

    result = element.element cond

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

    puts 'indent? : ' + @indent.inspect if @debug

    if @indent == true then
      doc_element.add_text  '  ' * (prev_indent > 0 ? prev_indent - 1 : prev_indent)
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

    puts 'children: ' + template_node.children.inspect if @debug
    template_node.children.each_with_index do |x,j|

      puts ('x: '  + x.inspect).debug if @debug
      name = if x.kind_of? Rexle::Element then :read_raw_element
      elsif x.is_a? String then :read_raw_text
      elsif x.class.to_s =~  /Rexle::Comment$/ then :ignore
      else
        :ignore
      end
      puts ('name: ' + name.inspect).debug if @debug

      r2 = method(name).call(element, x, doc_element, indent, i)
      puts 'r2b: ' + r2.inspect if @debug
      r2

    end

  end

  # element: xml source element, x: xsl element, doc_element: current destination xml element
  #
  def read_raw_text(element, x, doc_element, raw_indent, i)

    #val = @indent == true ? padding(doc_element, raw_indent, x) : ''
    if x.to_s.strip.length > 0 then

      val = x.to_s.strip #
      puts ('val: ' + val.inspect).debug if @debug
      doc_element.add_element x.to_s
    end

  end

  # element: xml element
  # x: xsl element
  # doc_element:
  #
  def read_raw_element(element, x, doc_element, indent, j)

    method_name = x.name.gsub(/[:-]/,'_').to_sym
    puts ('method_name: ' + method_name.inspect).debug if @debug

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

        puts 'v: ' + v.inspect if @debug

        if v[/{/] then

          v.gsub!(/(\{[^\}]+\})/) do |x2|

            xpath = x2[/\{([^\}]+)\}/,1]
            puts 'element.text(xpath): ' + element.text(xpath).inspect if @debug
            text = element.text(xpath).to_s.strip
            puts 'text: ' + text.inspect if @debug
            text ? text.clone : ''

          end

          puts '2. v: ' + v.inspect if @debug

        end
      end

      puts 'x.children.length: ' + x.children.length.inspect if @debug

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

        indent_before(element, x, new_element, new_indent, j) if @indent == true

        val = @indent == true ? x.to_s : x.to_s
        #jr020219 doc_element.add val
        doc_element.add new_element

      end

    end
    #new_element
    #puts 'attributes: ' + new_element.attributes.inspect if @debug

  end

  def value_of(x, elementx, i)

    puts 'value_of: ' + elementx.to_s.inspect if @debug

    field = x.attributes[:select]

    o = case field
      when '.'
        elementx.value
      when /^\$/
        @param[field[/^\$(.*)/,1]]
      when 'position()'
        i.to_s
    else
      r = elementx.element(field)
      if r.is_a? Rexle::Element::Attribute
        r.value.to_s
      elsif r.is_a? Rexle::Element
        r.texts.join
      else
        ''
      end

    end

  end

  def xsl_output()

  end

  def xsl_text(element, x, doc_element, indent, i)

    puts ('inside xsl_text x.value:' + x.inspect).debug if @debug
    val = @indent == true ? padding(doc_element, indent, x) : ''

    val += if x.attributes[:"disable-output-escaping"] then
      x.value.unescape
    else
      x.value.to_s
    end

    doc_element.add_element val

  end

  def xsl_value_of(element, x, doc_element, indent, i)

    #puts 'xsl_value_of: ' + x.inspect if @debug
    s = value_of(x, element,i)
    puts ('xsl_value_of s: ' + s.inspect).debug if @debug

    doc_element.add_text  s
    doc_element

  end


  def xslt_transform(raw_xsl, xml, custom_params={})

    puts 'inside xslt_transform'.info if @debug

    doc_xml = xml.is_a?(Rexle) ? xml : Rexle.new(xml)

    @doc_xsl = raw_xsl.is_a?(Rexle) ? raw_xsl : Rexle.new(raw_xsl.gsub(/(?<=\<\/xsl:text>)[^<]+/,''))
    puts 'after @doc_xsl'.info if @debug

    #jr2040516 filter_out_spaces @doc_xsl.root

    @doc = Rexle.new '<root4></root4>', debug: @debug

    indent = 0

    previous_indent = 0
    @xsl_methods = %i(apply_templates value_of element if choose when copy_of
                      attribute for_each text output call_template comment cdata).map do |x|
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
    puts 'h: ' + h.inspect if @debug
    puts 'after h'.info if @debug

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

    puts ('out: ' + out.inspect).debug if @debug

    html = @doc.root.element('html')

    if html then

        if h and h[:'omit-xml-declaration'] != 'yes'  then
        else
          @options[:declaration] = :none
        end

    end

    if @doc_xsl.root.element('xsl:output[@method="html"]') or html then

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
