# frozen_string_literal: true

require "set"

module Grsx
  # Shared element constants for the GRSX pipeline.
  #
  # Canonical source of truth for HTML, SVG, and void element sets.
  # Referenced by Parser, Codegen, Preprocessor, and ComponentResolver.
  #
  module Elements
    # HTML5 void elements — self-closing, cannot have children.
    VOID = %w(
      area base br col embed hr img input link meta source track wbr
    ).to_set.freeze

    # SVG-specific elements — rendered via Phlex's yielded SVG receiver.
    # Inside <svg>, these become s.circle(...), s.path(...), etc.
    SVG = %w(
      circle clipPath defs desc ellipse feBlend feColorMatrix feComponentTransfer
      feComposite feConvolveMatrix feDiffuseLighting feDisplacementMap feDropShadow feFlood
      feFuncA feFuncB feFuncG feFuncR feGaussianBlur feImage feMerge feMergeNode feMorphology
      feOffset feSpecularLighting feTile feTurbulence filter foreignObject g image line
      linearGradient marker mask metadata mpath path pattern polygon polyline radialGradient
      rect set stop symbol textPath tspan use view
    ).to_set.freeze

    # All known HTML5 + SVG elements.
    # Used to distinguish <html_tag> from <ComponentTag>.
    KNOWN = %w(
      a abbr address area article aside audio b base bdi bdo blockquote body br button canvas
      caption cite code col colgroup data datalist dd del details dfn dialog div dl dt em embed
      fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hgroup hr html i
      iframe img input ins kbd label legend li link main map mark menu meta meter nav noscript
      object ol optgroup option output p param picture pre progress q rp rt ruby s samp script
      search section select slot small source span strong style sub summary sup table tbody td
      template textarea tfoot th thead time title tr track u ul var video wbr
      svg circle clipPath defs desc ellipse feBlend feColorMatrix feComponentTransfer
      feComposite feConvolveMatrix feDiffuseLighting feDisplacementMap feDropShadow feFlood
      feFuncA feFuncB feFuncG feFuncR feGaussianBlur feImage feMerge feMergeNode feMorphology
      feOffset feSpecularLighting feTile feTurbulence filter foreignObject g image line
      linearGradient marker mask metadata mpath path pattern polygon polyline radialGradient
      rect set stop symbol textPath tspan use view
    ).to_set.freeze

    # JSX convention → HTML equivalent corrections.
    # Auto-corrects with a development warning when used.
    JSX_ATTR_CORRECTIONS = {
      "className"   => "class",
      "htmlFor"     => "for",
      "tabIndex"    => "tabindex",
      "autoFocus"   => "autofocus",
      "autoPlay"    => "autoplay",
      "autoComplete" => "autocomplete",
      "crossOrigin" => "crossorigin",
      "readOnly"    => "readonly",
      "maxLength"   => "maxlength",
      "minLength"   => "minlength",
      "noValidate"  => "novalidate",
      "formAction"  => "formaction",
      "formMethod"  => "formmethod",
      "formTarget"  => "formtarget",
      "srcSet"      => "srcset",
      "useMap"      => "usemap",
      "cellPadding" => "cellpadding",
      "cellSpacing" => "cellspacing",
      "colSpan"     => "colspan",
      "rowSpan"     => "rowspan",
      "encType"     => "enctype",
      "accessKey"   => "accesskey",
      "contentEditable" => "contenteditable",
    }.freeze
  end
end
