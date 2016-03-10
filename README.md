# Introducing the Rexslt gem

    require 'rexslt'


    xsl =<<XSL
    <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">

      <xsl:template match="game">
        <xsl:apply-templates select="memory"/>
      </xsl:template>

      <xsl:template match="memory">
        <xsl:value-of select="digits"/>
      </xsl:template>

    </xsl:stylesheet>
    XSL

    xml = "
    <game>
      <memory><digits>123</digits></memory>
      <memory><digits>111</digits></memory>
    </game>"

    puts Rexslt.new(xsl, xml).to_s

<pre>&lt;?xml version='1.0' encoding='UTF-8'?&gt;123111</pre>

## Resources

* rexslt https://rubygems.org/gems/rexslt

rexslt xslt xml gem transform

