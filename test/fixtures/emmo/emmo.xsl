<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="2.0"
  exclude-result-prefixes="tei"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

<!-- HTML output so empty non-void elements (e.g. <del/>) serialize with a
     closing tag (<del></del>). XML serialization self-closes them as <del/>,
     which HTML5 reads as an unclosed <del> that strikes through the rest of
     the page. -->
<xsl:output method="html" omit-xml-declaration="yes" encoding="utf-8"/>

<xsl:param name="rdg" select="'semiDiplomatic'"/>

<xsl:strip-space elements="*"/>
<xsl:preserve-space elements="tei:c"/>

<xsl:template match="/">
  <xsl:apply-templates/>
</xsl:template>

<xsl:template match="tei:teiHeader"/>
<xsl:template match="tei:fw"/>
<xsl:template match="tei:note"/>

<xsl:template match="tei:div">
  <span style="left: 75px;"><xsl:apply-templates/><br/><br/></span>
</xsl:template>

<xsl:template match="tei:opener">
  <br/><xsl:value-of select="tei:opener"/><br/><xsl:apply-templates/>
</xsl:template>

<xsl:template match="tei:p"><xsl:apply-templates/></xsl:template>
<xsl:template match="tei:lb"><br/></xsl:template>

<xsl:template match="tei:lb[@break='no']">
  <xsl:choose>
    <xsl:when test="$rdg='diplomatic'"><br/></xsl:when>
    <xsl:when test="$rdg='semiDiplomatic'"><br/></xsl:when>
    <xsl:otherwise/>
  </xsl:choose>
</xsl:template>

<xsl:template match="tei:lb[@break='reg']">
  <xsl:if test="$rdg='regularized'"><br/></xsl:if>
</xsl:template>

<xsl:template match="tei:closer">
  <br/><div style="padding-left:40px;"><xsl:apply-templates/></div>
</xsl:template>

<xsl:template match="tei:note[@type='administrative' and @subtype='endorsement']">
  <span style="left: 75px; color:gray;"><xsl:apply-templates/><br/></span>
</xsl:template>

<xsl:template match="tei:note[@type='authorial']">
  <span style="left: 75px; color:gray;"><xsl:apply-templates/></span>
</xsl:template>

<xsl:template match="tei:note[@type='editorial']">
  <xsl:if test="$rdg='regularized'">
    <span style="padding: 0px 5px; color:gray;">[<xsl:apply-templates/>]</span>
  </xsl:if>
</xsl:template>

<xsl:template match="tei:figure/tei:desc">
  <span style="left: 75px; color:gray;">[<xsl:apply-templates/>]</span>
</xsl:template>

<!-- Expansions -->
<xsl:template match="tei:ex">
  <xsl:if test="$rdg='semiDiplomatic'">
    <span style="font-style:italic;"><xsl:apply-templates/></span>
  </xsl:if>
</xsl:template>

<xsl:template match="tei:expan">
  <xsl:if test="$rdg='semiDiplomatic'"><xsl:apply-templates/></xsl:if>
</xsl:template>

<xsl:template match="tei:g[@ref='#thorn']">
  <xsl:choose>
    <xsl:when test="$rdg='diplomatic'">y</xsl:when>
    <xsl:when test="$rdg='semiDiplomatic'">
      <span style="font-style:italic;">th</span>
    </xsl:when>
    <xsl:otherwise>th</xsl:otherwise>
  </xsl:choose>
</xsl:template>

<!-- Regularization / Original -->
<xsl:template match="tei:reg">
  <xsl:if test="$rdg='regularized'"><xsl:apply-templates/></xsl:if>
</xsl:template>

<xsl:template match="tei:reg[@xml:lang]">
  <xsl:if test="$rdg='regularized' and @xml:lang='en'">
    <xsl:apply-templates/>
  </xsl:if>
</xsl:template>

<xsl:template match="tei:orig">
  <xsl:if test="$rdg!='regularized'"><xsl:apply-templates/></xsl:if>
</xsl:template>

<!-- Formatting -->
<xsl:template match="tei:hi[@rend='superscript']"><sup><xsl:apply-templates/></sup></xsl:template>
<xsl:template match="tei:del"><del><xsl:apply-templates/></del></xsl:template>

<xsl:template match="tei:add[@type='authorial']">
  <xsl:choose>
    <xsl:when test="$rdg='regularized'"><xsl:apply-templates/></xsl:when>
    <xsl:otherwise><sup><xsl:apply-templates/></sup></xsl:otherwise>
  </xsl:choose>
</xsl:template>

<!-- Metamarks -->
<xsl:template match="tei:metamark[@function='insertion']">
  <xsl:if test="$rdg!='regularized'">
    <span style="position:relative; top:10px;"><xsl:apply-templates/></span>
  </xsl:if>
</xsl:template>

<xsl:template match="tei:metamark[@function='expansion']">
  <xsl:if test="$rdg='diplomatic'"><xsl:apply-templates/></xsl:if>
</xsl:template>

<!-- Abbreviations -->
<xsl:template match="tei:abbr[@type='abbreviation']">
  <xsl:if test="$rdg='diplomatic'"><xsl:apply-templates/></xsl:if>
</xsl:template>

<xsl:template match="tei:abbr[@type='superscription']">
  <xsl:choose>
    <xsl:when test="$rdg='diplomatic'"><sup><xsl:apply-templates/></sup></xsl:when>
    <xsl:otherwise><xsl:apply-templates/></xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template match="tei:abbr[@type='ordinal']//tei:abbr[@type='superscription']">
  <xsl:choose>
    <xsl:when test="$rdg='regularized'"><xsl:apply-templates/></xsl:when>
    <xsl:otherwise><sup><xsl:apply-templates/></sup></xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template match="tei:abbr[@type='superscription' and @subtype='currency']">
  <sup><xsl:apply-templates/></sup>
</xsl:template>

<xsl:template match="tei:abbr[@type='macron']">
  <xsl:choose>
    <xsl:when test="$rdg='diplomatic'"><span style="text-decoration: overline;"><xsl:apply-templates/></span></xsl:when>
    <xsl:otherwise><xsl:apply-templates/></xsl:otherwise>
  </xsl:choose>
</xsl:template>

<!-- Brevigraphs: generic fallback -->
<xsl:template match="tei:abbr[@type='brevigraph']">
  <span style="font-style:italic;"><xsl:apply-templates/></span>
</xsl:template>

<!-- Brevigraphs: specific subtypes (higher priority) -->
<xsl:template match="tei:abbr[@type='brevigraph' and @subtype='brev-p']" priority="1">
  <xsl:choose>
    <xsl:when test="$rdg='diplomatic'"><span class="extended">&#xa751;</span></xsl:when>
    <xsl:otherwise><xsl:apply-templates/></xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template match="tei:abbr[@type='brevigraph' and @subtype='brev-er']" priority="1">
  <xsl:choose>
    <xsl:when test="$rdg='diplomatic'">{<xsl:apply-templates/>}</xsl:when>
    <xsl:when test="$rdg='semiDiplomatic'"><span style="font-style:italic;"><xsl:apply-templates/></span></xsl:when>
    <xsl:otherwise><xsl:apply-templates/></xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template match="tei:abbr[@type='brevigraph' and @subtype='brev-es']" priority="1">
  <xsl:choose>
    <xsl:when test="$rdg='diplomatic'">{<xsl:apply-templates/>}</xsl:when>
    <xsl:when test="$rdg='semiDiplomatic'"><span style="font-style:italic;"><xsl:apply-templates/></span></xsl:when>
    <xsl:otherwise><xsl:apply-templates/></xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template match="tei:abbr[@type='brevigraph' and @subtype='brev-s']" priority="1">
  <xsl:choose>
    <xsl:when test="$rdg='diplomatic'"><span class="extended">&#x00df;</span></xsl:when>
    <xsl:when test="$rdg='semiDiplomatic'"><span style="font-style:italic;"><xsl:apply-templates/></span></xsl:when>
    <xsl:otherwise><xsl:apply-templates/></xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template match="tei:abbr[@type='brevigraph' and @subtype='truncation-z']" priority="1">
  <xsl:choose>
    <xsl:when test="$rdg='diplomatic'"><span style="font-style:italic;">z</span></xsl:when>
    <xsl:when test="$rdg='semiDiplomatic'"><span style="font-style:italic;"><xsl:apply-templates/></span></xsl:when>
    <xsl:otherwise><xsl:apply-templates/></xsl:otherwise>
  </xsl:choose>
</xsl:template>

<!-- Supplied text -->
<xsl:template match="tei:supplied[@reason='missing']">
  <xsl:if test="$rdg='semiDiplomatic'">[<xsl:apply-templates/>]</xsl:if>
</xsl:template>

<xsl:template match="tei:supplied[@reason='damaged']">
  <xsl:choose>
    <xsl:when test="$rdg='diplomatic'">[<xsl:value-of select="'&#9671;'"/>]</xsl:when>
    <xsl:when test="$rdg='semiDiplomatic'">[<xsl:apply-templates/>]</xsl:when>
    <xsl:otherwise/>
  </xsl:choose>
</xsl:template>

<xsl:template match="tei:gap">[<xsl:value-of select="'&#9671;'"/>]</xsl:template>

<!-- Page breaks -->
<xsl:template match="tei:pb">
  <h2 id="{@n}"><xsl:value-of select="@n"/></h2>
</xsl:template>

</xsl:stylesheet>
