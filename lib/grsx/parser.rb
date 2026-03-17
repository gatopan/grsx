# frozen_string_literal: true

require "strscan"

module Grsx
  # Recursive-descent parser for RSX source.
  #
  # Consumes RSX source (Ruby + <Tag> extensions) and produces an AST.
  # Uses StringScanner as an integrated lexer — the parser tokenizes
  # on demand because RSX is modal (same characters mean different
  # things in Ruby context vs children context vs attribute context).
  #
  # Usage:
  #   ast = Grsx::Parser.new(source, resolver: resolver).parse
  #   # => [AST::RubyCode(...), AST::Tag(...), ...]
  #
  class Parser
    attr_reader :resolver

    def initialize(source, resolver: nil)
      @source = source
      @scanner = StringScanner.new(source)
      @line = 1
      @col = 0  # TODO: track column for IDE-quality diagnostics
      @tag_stack = []
      @svg_depth = 0
      @resolver = resolver || Grsx.resolver
    end

    # Parse the entire source into a list of AST nodes.
    def parse
      nodes = parse_ruby_context

      unless @tag_stack.empty?
        unclosed = @tag_stack.last
        tag_desc = unclosed[:name].empty? ? "fragment (<>)" : "<#{unclosed[:name]}>"
        raise Grsx::SyntaxError.new(
          "Unclosed tag #{tag_desc} — opened on line #{unclosed[:line]}, never closed",
          line: unclosed[:line], source: @source
        )
      end

      nodes
    end

    private

    def loc
      AST::Location.new(line: @line, col: @col)
    end

    def track_newlines(text)
      @line += text.count("\n") if text
    end

    # ── Ruby Context ──────────────────────────────────────────────
    # Default mode. Collects Ruby code verbatim, intercepts <Tag> patterns.
    #
    # When block_mode is true (called from {expr do} block bodies),
    # tracks keyword depth and terminates at bare `end` when depth
    # reaches 0. This enables infinite Ruby/RSX alternation:
    #
    #   parse_ruby_context → <tag> → parse_children → {expr do} → parse_ruby_context → ...

    def parse_ruby_context(block_mode: false)
      nodes = []
      ruby_buf = +""
      keyword_depth = 0
      open_line = @line

      flush_ruby = -> {
        unless ruby_buf.empty?
          nodes << AST::RubyCode.new(source: ruby_buf, location: loc)
          ruby_buf = +""
        end
      }

      at_line_start = -> {
        @col == 0 || @source[0...@scanner.pos].match?(/(?:\A|\n)[ \t]*\z/)
      }

      while !@scanner.eos?
        # ── Block mode: end} (RSX definitive closer) ──
        if block_mode && @scanner.check(/[ \t]*\bend\b\s*\}/)
          flush_ruby.call
          @scanner.scan(/[ \t]*\bend/)
          @scanner.scan(/\s*/)
          @scanner.scan(/\}/) # consume }
          nodes << AST::RubyCode.new(source: "end\n", location: loc)
          return nodes
        end

        # ── Block mode: bare `end` (depth-tracked) ──
        if block_mode && @scanner.check(/[ \t]*\bend\b\s*(?:\n|\z)/)
          if keyword_depth <= 0
            flush_ruby.call
            @scanner.scan(/[ \t]*\bend\b/)
            @scanner.scan(/\s*/)
            nodes << AST::RubyCode.new(source: "end\n", location: loc)
            return nodes
          else
            keyword_depth -= 1
            chunk = @scanner.scan(/[^\n]*/)
            ruby_buf << chunk
            next
          end
        end

        # Skip strings and Ruby comments — preserve in output
        if (skipped = try_skip_string || try_skip_comment)
          ruby_buf << skipped
          next
        end

        # HTML comments are stripped entirely (not emitted)
        if try_skip_html_comment
          next
        end

        # Check for tag opening
        if @scanner.check(/<(?=[A-Z\/a-z>])/)
          tag_node = try_parse_tag_or_close
          if tag_node
            flush_ruby.call
            nodes << tag_node
            next
          end
        end

        # ── Block mode: track Ruby keyword depth ──
        if block_mode && at_line_start.call && @scanner.check(/[ \t]*(?:if|unless|case|begin|for|while|until|class|def|module)\b/)
          keyword_depth += 1
          # Don't consume the whole line, let the bulk scanner get it.
          # Just consume the spaces and keyword so we don't count it again.
          ruby_buf << @scanner.scan(/[ \t]*(?:if|unless|case|begin|for|while|until|class|def|module)\b/)
          next
        end

        # Bulk copy Ruby code — stop at newlines in block mode
        # so we can check for bare `end` on the next iteration
        stop_chars = block_mode ? /[^\n<"'`#%]+/ : /[<"'`#%]+/
        chunk = @scanner.scan(stop_chars)
        if chunk
          if block_mode
            # Track `do` blocks opened anywhere on the line
            keyword_depth += chunk.scan(/\bdo\b/).count
          end
          ruby_buf << chunk
          @line += chunk.count("\n")
          next
        end

        # Newline
        if @scanner.check(/\n/)
          ch = @scanner.getch
          @line += 1
          ruby_buf << ch
          next
        end

        # Single character passthrough
        ch = @scanner.getch
        @line += 1 if ch == "\n"
        ruby_buf << ch
      end

      if block_mode
        raise Grsx::SyntaxError.new(
          "Unclosed block expression — opened on line #{open_line}, expected end",
          line: open_line, source: @source
        )
      end

      flush_ruby.call
      nodes
    end

    # ── Children Context ──────────────────────────────────────────
    # Inside a tag body. Grammar is deterministic LL(1):
    #
    #   children := (child)*
    #   child    := tag | expression | text
    #   tag      := '<' name attrs '>' children '</' name '>'
    #   expression := '{' ruby_code '}'
    #   text     := [^<{]+  (everything that isn't a tag or expression)
    #
    # The first character determines the production:
    #   '<'  → tag or close-tag
    #   '{'  → expression (Ruby code)
    #   else → text content
    #
    # Ruby code in children MUST be wrapped in {}.
    # All bare content is text by definition — no heuristic needed.

    def parse_children(parent_tag)
      nodes = []
      ruby_buf = +""

      flush_ruby = -> {
        unless ruby_buf.empty?
          nodes << AST::RubyCode.new(source: ruby_buf, location: loc)
          ruby_buf = +""
        end
      }

      while !@scanner.eos?
        # ── Close tag: '</' ──
        if @scanner.check(%r{</})
          if peek_close_tag(parent_tag)
            flush_ruby.call
            consume_close_tag(parent_tag)
            return nodes
          else
            # Mismatch
            if @scanner.check(%r{</\s*([A-Za-z][A-Za-z0-9\-_\.]*)\s*>})
              actual = @scanner.matched&.slice(/[A-Za-z][A-Za-z0-9\-_\.]*/) || "?"
              raise Grsx::SyntaxError.new(
                "Mismatched closing tag: expected </#{parent_tag}>, got </#{actual}>",
                line: @line, source: @source
              )
            end
            ch = @scanner.getch
            @line += 1 if ch == "\n"
            ruby_buf << ch
            next
          end
        end

        # ── HTML comments: '<!--' ──
        if (comment = try_skip_html_comment)
          next
        end

        # ── Nested tag or fragment: '<' ──
        if @scanner.check(/<(?=[A-Z\/a-z>])/)
          tag_node = try_parse_tag_or_close
          if tag_node
            flush_ruby.call
            nodes << tag_node
            next
          end
        end

        # ── Expression: '{' ──
        if @scanner.check(/\{/)
          flush_ruby.call
          nodes << parse_children_expression
          next
        end



        # ── Text content: everything else ──
        # Deterministic rule: all non-tag, non-expression content in
        # children context is text. Scan up to the next delimiter.
        if @scanner.check(/[^\n<{]+/)
          text = @scanner.scan(/[^\n<{]+/)
          stripped = text.strip

          if stripped.empty?
            # Whitespace-only — structural indentation between elements.
            # Preserved as RubyCode for codegen spacing decisions.
            ruby_buf << text
          else
            # Text content. Accumulate continuation lines: keep consuming
            # across newlines as long as the next line has non-whitespace
            # content that isn't a tag/expression/close-tag opener.
            flush_ruby.call
            has_leading_space = text != text.lstrip
            text_loc = loc
            full_text = stripped

            while @scanner.check(/\n[ \t]*[^\n<{}\s]/)
              saved_pos = @scanner.pos
              saved_line = @line

              @scanner.scan(/\n[ \t]*/)
              @line += 1



              next_chunk = @scanner.scan(/[^\n<{]+/)
              if next_chunk && !next_chunk.strip.empty?
                full_text = full_text + " " + next_chunk.strip
              else
                # Next content is a tag, expression, or whitespace-only line.
                # Rewind and let the main loop handle it.
                @scanner.pos = saved_pos
                @line = saved_line
                break
              end
            end

            has_trailing_space = text != text.rstrip
            nodes << AST::Text.new(
              content: full_text,
              leading_space: has_leading_space,
              trailing_space: has_trailing_space,
              location: text_loc
            )
          end
          next
        end

        # ── Newlines ──
        ch = @scanner.getch
        @line += 1 if ch == "\n"
        ruby_buf << ch
      end

      flush_ruby.call
      nodes
    end

    # ── Tag Parsing ───────────────────────────────────────────────

    def try_parse_tag_or_close
      # Fragment opener: <>
      if @scanner.scan(/<>/)
        @tag_stack.push({ name: "", line: @line })
        children = parse_children("")
        return AST::Fragment.new(children: children, location: loc)
      end

      # Open tag: <tagName
      if @scanner.scan(/<([A-Za-z][A-Za-z0-9\-_.:]*)/x)
        tag_name = @scanner[1]

        if html_element?(tag_name)
          return parse_html_tag(tag_name)
        elsif component_element?(tag_name)
          return parse_component_tag(tag_name)
        else
          suggestion = find_similar_element(tag_name)
          msg = "Unknown element <#{tag_name}>"
          msg += ". Did you mean <#{suggestion}>?" if suggestion
          msg += " (components must start with uppercase, e.g. <#{tag_name.capitalize}>)"
          raise Grsx::SyntaxError.new(msg, line: @line, source: @source)
        end
      end

      nil
    end

    def parse_html_tag(tag_name)
      open_line = @line
      attrs = parse_attributes(component: false)
      self_closing_text = @scanner.scan(/\s*\/?>/)
      track_newlines(self_closing_text)

      is_self_closing = self_closing_text&.include?("/") || Elements::VOID.include?(tag_name)
      entering_svg = tag_name == "svg" && !is_self_closing
      kind = @svg_depth > 0 && Elements::SVG.include?(tag_name) ? :svg : :html

      children = []
      unless is_self_closing
        @svg_depth += 1 if entering_svg
        @tag_stack.push({ name: tag_name, line: open_line, svg: entering_svg })
        children = parse_children(tag_name)
      end

      AST::Tag.new(
        name: tag_name,
        attrs: attrs,
        children: children,
        self_closing: is_self_closing,
        kind: kind,
        location: AST::Location.new(line: open_line, col: 0)
      )
    end

    def parse_component_tag(tag_name)
      open_line = @line
      attrs = parse_attributes(component: true)
      self_closing_text = @scanner.scan(/\s*\/?>/)
      track_newlines(self_closing_text)

      is_self_closing = self_closing_text&.include?("/")

      children = []
      unless is_self_closing
        @tag_stack.push({ name: tag_name, line: open_line })
        children = parse_children(tag_name)
      end

      AST::Tag.new(
        name: tag_name,
        attrs: attrs,
        children: children,
        self_closing: is_self_closing,
        kind: :component,
        location: AST::Location.new(line: open_line, col: 0)
      )
    end

    def peek_close_tag(expected_tag)
      if expected_tag == ""
        @scanner.check(%r{</>})
      else
        @scanner.check(%r{</\s*#{Regexp.escape(expected_tag)}\s*>})
      end
    end

    def consume_close_tag(expected_tag)
      if expected_tag == ""
        @scanner.scan(%r{</>})
        @tag_stack.pop
        return
      end

      if @scanner.scan(%r{</\s*([A-Za-z][A-Za-z0-9\-_\.]*)\s*>})
        actual = @scanner[1]
        if actual == expected_tag
          closed = @tag_stack.pop
          @svg_depth -= 1 if closed&.dig(:svg)
        else

          raise Grsx::SyntaxError.new(
            "Mismatched closing tag: expected </#{expected_tag}>, got </#{actual}>",
            line: @line, source: @source
          )
        end
      end
    end

    # ── Attribute Parsing ─────────────────────────────────────────

    def parse_attributes(component: false)
      attrs = []

      ws = @scanner.scan(/\s*/)
      track_newlines(ws)

      while !@scanner.eos?
        ws = @scanner.scan(/\s*/)
        track_newlines(ws)

        break if @scanner.check(/\s*\/?>/)

        # Splat: {**expr}
        if @scanner.scan(/\{\s*\*\*/)
          expr = scan_expression_content
          @scanner.scan(/\}/)
          attrs << AST::Attr.new(name: nil, value: AST::AttrValue.new(source: expr, kind: :dynamic), splat: true, location: loc)
          next
        end

        # Named attribute
        if @scanner.scan(/([A-Za-z][A-Za-z0-9\-_.:]*)\s*/x)
          attr_name = @scanner[1]

          if @scanner.scan(/=\s*/)
            val = parse_attr_value
            attr_name = correct_jsx_attr(attr_name) unless component
            next if component && attr_name == "key"
            attrs << AST::Attr.new(name: attr_name, value: val, location: loc)
          else
            next if component && attr_name == "key"
            attrs << AST::Attr.new(name: attr_name, value: nil, location: loc)
          end
          next
        end

        break
      end

      attrs
    end

    def parse_attr_value
      if @scanner.scan(/"/)
        val = scan_quoted_string('"')
        AST::AttrValue.new(source: val, kind: :static)
      elsif @scanner.scan(/'/)
        val = scan_quoted_string("'")
        AST::AttrValue.new(source: val, kind: :static)
      elsif @scanner.scan(/\{/)
        expr = scan_expression_content
        @scanner.scan(/\}/)
        AST::AttrValue.new(source: expr, kind: :dynamic)
      else
        val = @scanner.scan(/[^\s\/>]+/) || "true"
        AST::AttrValue.new(source: val, kind: :static)
      end
    end

    # ── Expression Handling ───────────────────────────────────────

    def parse_children_expression
      open_line = @line
      @scanner.scan(/\{/) # consume {

      preamble, block_detected = scan_braced_content(detect_block: true)

      # Unclosed expression detection
      if @scanner.eos? && !block_detected
        raise Grsx::SyntaxError.new(
          "Unclosed expression { opened on line #{open_line}",
          line: open_line, source: @source
        )
      end

      if block_detected
        # Check for statement pattern: {expr do |args|}
        # If the closing } follows right after the block args,
        # this is a statement-level block opener, not a block-with-body.
        if @scanner.check(/\s*\}/)
          @scanner.scan(/\s*\}/)
          AST::RubyCode.new(source: preamble.strip + "\n", location: loc)
        else
          # Block expression with RSX body: {link_to path do <i/> end}
          children = parse_ruby_context(block_mode: true)
          AST::BlockExpr.new(
            preamble: preamble.strip,
            children: children,
            location: loc
          )
        end
      else
        unless @scanner.scan(/\}/)
          raise Grsx::SyntaxError.new(
            "Unclosed expression { opened on line #{open_line}",
            line: open_line, source: @source
          )
        end
        expr = preamble.strip

        # Control flow statements: emit as bare Ruby code, not as
        # expression interpolation. These are statement-level constructs
        # that the user wraps in {} per the deterministic grammar.
        #   {if condition}  → emits: if condition
        #   {elsif cond}    → emits: elsif cond
        #   {else}          → emits: else
        #   {end}           → emits: end
        #   {begin}         → emits: begin
        #   {rescue => e}   → emits: rescue => e
        #   {ensure}        → emits: ensure
        control_flow_re = /\A(if|elsif|else|unless|case|when|begin|rescue|ensure|end|for|while|until)\b/
        if expr.match?(control_flow_re) || expr == "end"
          AST::RubyCode.new(source: expr + "\n", location: loc)
        else
          AST::Expr.new(source: expr, location: loc)
        end
      end
    end






    # ── Skip Logic ────────────────────────────────────────────────
    # These return the consumed string (for Ruby passthrough) or nil.

    def try_skip_string
      if @scanner.scan(/"/)
        raw = scan_quoted_string('"', raw: true)
        "\"#{raw}\""
      elsif @scanner.scan(/'/)
        raw = scan_quoted_string("'", raw: true)
        "'#{raw}'"
      elsif @scanner.scan(/`/)
        raw = scan_quoted_string("`", raw: true)
        "`#{raw}`"
      elsif @scanner.scan(/<<~?([A-Z_]+)/)
        heredoc_start = @scanner.matched
        tag = @scanner[1]
        body = @scanner.scan_until(/^#{tag}\b/) || @scanner.rest.tap { @scanner.terminate }
        track_newlines(body)
        "#{heredoc_start}#{body}"
      elsif @scanner.scan(/%([qQwWiIrsx])?([^A-Za-z0-9\s])/)
        prefix = @scanner.matched
        open_delim = @scanner[2]
        close_delim = matching_delimiter(open_delim)
        paired = open_delim != close_delim
        content = skip_delimited_content_returning(open_delim, close_delim, paired)
        "#{prefix}#{content}"
      else
        nil
      end
    end

    def try_skip_comment
      if @scanner.check(/\#/) && at_line_start?
        line = @scanner.scan_until(/\n/) || @scanner.rest.tap { @scanner.terminate }
        @line += 1 if line.include?("\n")
        line
      elsif @scanner.scan(/\#/)
        line = @scanner.scan_until(/\n/) || @scanner.rest.tap { @scanner.terminate }
        @line += 1 if line&.include?("\n")
        "##{line}"
      else
        nil
      end
    end

    def try_skip_html_comment
      if @scanner.scan(/<!--/)
        content = @scanner.scan_until(/-->/) || @scanner.rest.tap { @scanner.terminate }
        track_newlines(content)
        "<!--#{content}"
      else
        nil
      end
    end

    # ── String Scanning Helpers ───────────────────────────────────

    def scan_quoted_string(quote, raw: false)
      result = +""
      while !@scanner.eos?
        if @scanner.scan(/\\#{Regexp.escape(quote)}/)
          result << (raw ? "\\" + quote : quote)
        elsif @scanner.check(/#{Regexp.escape(quote)}/)
          @scanner.getch
          break
        else
          ch = @scanner.getch
          @line += 1 if ch == "\n"
          result << ch
        end
      end
      result
    end

    # Shared brace-depth-tracking scanner.
    # Returns [content_string, block_detected].
    # When detect_block is true, stops at bare `do` keyword.
    def scan_braced_content(detect_block: false)
      result = +""
      depth = 0
      block_detected = false

      while !@scanner.eos?
        if @scanner.check(/\}/) && depth == 0
          break
        elsif @scanner.scan(/\{/)
          depth += 1
          result << "{"
        elsif @scanner.scan(/\}/)
          depth -= 1
          result << "}"
        elsif @scanner.scan(/"/)
          result << '"' << scan_quoted_string('"', raw: true) << '"'
        elsif @scanner.scan(/'/)
          result << "'" << scan_quoted_string("'", raw: true) << "'"
        elsif detect_block && @scanner.scan(/\bdo\b(\s*\|[^|]*\|)?/)
          result << @scanner.matched
          block_detected = true
          break
        else
          ch = @scanner.getch
          @line += 1 if ch == "\n"
          result << ch
        end
      end

      [result, block_detected]
    end

    def scan_expression_content
      open_line = @line
      result, _ = scan_braced_content

      if @scanner.eos? && !@scanner.check(/\}/)
        raise Grsx::SyntaxError.new(
          "Unclosed expression { opened on line #{open_line}",
          line: open_line, source: @source
        )
      end

      result.strip
    end

    # ── Utility ───────────────────────────────────────────────────

    def matching_delimiter(open)
      case open
      when "(" then ")"
      when "[" then "]"
      when "{" then "}"
      when "<" then ">"
      else open
      end
    end

    def skip_delimited_content_returning(open_delim, close_delim, paired)
      result = +""
      depth = 0
      open_re  = Regexp.escape(open_delim)
      close_re = Regexp.escape(close_delim)

      while !@scanner.eos?
        if paired && @scanner.scan(/#{open_re}/)
          depth += 1
          result << open_delim
        elsif @scanner.scan(/#{close_re}/)
          if depth == 0
            result << close_delim
            break
          end
          depth -= 1
          result << close_delim
        elsif @scanner.scan(/\\./m)
          result << @scanner.matched
          @line += 1 if @scanner.matched.include?("\n")
        else
          ch = @scanner.getch
          @line += 1 if ch == "\n"
          result << ch
        end
      end

      result
    end

    def at_line_start?
      @scanner.pos == 0 || @source[@scanner.pos - 1] == "\n"
    end

    def html_element?(name)
      Elements::KNOWN.include?(name)
    end

    def component_element?(name)
      name[0] == name[0].upcase
    end

    def find_similar_element(name)
      best = nil
      best_dist = Float::INFINITY
      Elements::KNOWN.each do |el|
        next if (el.length - name.length).abs > 2
        dist = simple_edit_distance(name, el)
        if dist < best_dist && dist <= 2
          best_dist = dist
          best = el
        end
      end
      best
    end

    def simple_edit_distance(a, b)
      return b.length if a.empty?
      return a.length if b.empty?
      matrix = Array.new(a.length + 1) { Array.new(b.length + 1, 0) }
      (0..a.length).each { |i| matrix[i][0] = i }
      (0..b.length).each { |j| matrix[0][j] = j }
      (1..a.length).each do |i|
        (1..b.length).each do |j|
          cost = a[i - 1] == b[j - 1] ? 0 : 1
          matrix[i][j] = [matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost].min
        end
      end
      matrix[a.length][b.length]
    end

    def correct_jsx_attr(name)
      if (corrected = Elements::JSX_ATTR_CORRECTIONS[name])
        warn "[GRSX] JSX convention: '#{name}' → '#{corrected}' (line #{@line}). RSX uses standard HTML attribute names."
        return corrected
      end
      if name.match?(/\Aon[A-Z]/)
        event = name.sub(/\Aon/, "").downcase
        warn "[GRSX] JSX convention: '#{name}' has no effect in server-rendered RSX (line #{@line}). " \
             "Use Stimulus: data-action=\"#{event}->controller#method\" instead."
      end
      name
    end
  end
end
