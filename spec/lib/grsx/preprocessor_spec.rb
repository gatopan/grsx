# frozen_string_literal: true

require "spec_helper"

RSpec.describe Grsx::Preprocessor do
  subject(:preprocessor) { described_class.new }

  def preprocess(source)
    preprocessor.preprocess(source)
  end

  def render(source, **init_args, &block)
    compiled = preprocess(source)
    klass = Class.new(Grsx::PhlexComponent)
    klass.instance_variable_set(:@_rsx_template_path, nil)
    klass.class_eval(&block) if block
    klass.class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
      def view_template
        #{compiled}
      end
    RUBY
    klass.new(**init_args).call
  end

  # ═══════════════════════════════════════════════════════════════
  # BASE CASES — every fundamental feature
  # ═══════════════════════════════════════════════════════════════

  describe "HTML elements" do
    it "converts a self-closing void element: <br />" do
      expect(render("<br />")).to include("<br>")
    end

    it "converts a self-closing non-void element: <div />" do
      result = preprocess("<div />")
      expect(result.strip).to eq("div")
    end

    it "converts an open+close element with text: <p>hi</p>" do
      html = render("<p>hi</p>")
      expect(html).to eq("<p>hi</p>")
    end

    it "converts nested elements" do
      html = render("<div><span>x</span></div>")
      expect(html).to include("<div><span>x</span></div>")
    end

    it "handles all void elements without explicit self-close" do
      %w[area base br col embed hr img input link meta source track wbr].each do |tag|
        html = render("<#{tag}>")
        expect(html).to include("<#{tag}")
      end
    end

    it "converts a tag with a single static attribute" do
      html = render('<a href="/x">go</a>')
      expect(html).to include('href="/x"')
    end

    it "converts a tag with multiple static attributes" do
      html = render('<input type="text" name="q" placeholder="search" />')
      expect(html).to include('type="text"')
      expect(html).to include('name="q"')
      expect(html).to include('placeholder="search"')
    end

    it "converts a tag with a dynamic attribute" do
      html = render('<a href={@url}>go</a>', url: "/y") { props :url }
      expect(html).to include('href="/y"')
    end

    it "converts a tag with a boolean attribute" do
      html = render("<button disabled>x</button>")
      expect(html).to include("disabled")
    end

    it "converts kebab-case attributes to underscore" do
      result = preprocess('<div data-controller="foo"></div>')
      expect(result).to include("data_controller:")
    end

    it "converts aria-label to aria_label" do
      result = preprocess('<div aria-label="x"></div>')
      expect(result).to include("aria_label:")
    end

    it "converts a splat attribute" do
      html = render('<div {**@a}>x</div>', a: { id: "z" }) { props :a }
      expect(html).to include('id="z"')
    end

    it "renders an empty element (no children, no text)" do
      html = render("<div></div>")
      expect(html).to include("<div></div>")
    end
  end

  describe "component elements" do
    before do
      stub_const("SimpleComponent", Class.new(Grsx::PhlexComponent) {
        template "<em>simple</em>"
      })
      stub_const("PropsComponent", Class.new(Grsx::PhlexComponent) {
        props :label
        template "<span>{@label}</span>"
      })
      stub_const("ChildrenComponent", Class.new(Grsx::PhlexComponent) {
        template '<div class="wrap">{content}</div>'
      })
    end

    it "renders a self-closing component" do
      html = render("<Simple />")
      expect(html).to include("<em>simple</em>")
    end

    it "renders a component with a static prop" do
      html = render('<Props label="hi" />')
      expect(html).to include("hi")
    end

    it "renders a component with a dynamic prop" do
      html = render("<Props label={@x} />", x: "dynamic") { props :x }
      expect(html).to include("dynamic")
    end

    it "renders a component with children (yield)" do
      html = render("<Children><p>child</p></Children>")
      expect(html).to include("<p>child</p>")
      expect(html).to include('class="wrap"')
    end

    it "strips the key prop from components" do
      html = render('<Simple key="1" />')
      expect(html).to include("simple")
    end
  end

  describe "expression interpolation" do
    it "renders {expr} as output in text context" do
      html = render("<p>Hello {name}</p>") { define_method(:name) { "W" } }
      expect(html).to include("Hello")
      expect(html).to include("W")
    end

    it "renders {content} as yield" do
      result = preprocess("<div>{content}</div>")
      expect(result).to include("yield")
      expect(result).not_to include("__rsx_expr_out")
    end

    it "auto-escapes HTML in expressions (XSS)" do
      html = render("<p>{@v}</p>", v: "<script>x</script>") { props :v }
      expect(html).to include("&lt;script&gt;")
      expect(html).not_to include("<script>")
    end

    it "outputs nothing for nil" do
      html = render("<p>{nil}</p>")
      expect(html).to eq("<p></p>")
    end

    it "outputs nothing for false" do
      html = render("<p>{false}</p>")
      expect(html).to eq("<p></p>")
    end

    it "renders integer expressions" do
      html = render("<p>{42}</p>")
      expect(html).to include("42")
    end

    it "renders method call expressions" do
      html = render('<p>{"hello".upcase}</p>')
      expect(html).to include("HELLO")
    end

    it "renders ternary expressions" do
      html = render('<p>{true ? "yes" : "no"}</p>')
      expect(html).to include("yes")
    end

    it "renders nested brace expressions" do
      html = render('<p>{{ a: 1 }.keys.first}</p>')
      expect(html).to include("a")
    end
  end

  describe "fragments" do
    it "renders children without a wrapper" do
      html = render("<><h1>A</h1><p>B</p></>")
      expect(html).to include("<h1>A</h1>")
      expect(html).to include("<p>B</p>")
      expect(html).not_to match(/<div|<span|<section/)
    end

    it "renders a fragment with a single child" do
      html = render("<><p>only</p></>")
      expect(html).to eq("<p>only</p>")
    end
  end

  describe "Ruby control flow" do
    it "if/end" do
      expect(render("if true\n  <b>y</b>\nend")).to include("<b>y</b>")
    end

    it "if/else/end" do
      html = render("if false\n  <b>y</b>\nelse\n  <i>n</i>\nend")
      expect(html).to include("<i>n</i>")
      expect(html).not_to include("<b>")
    end

    it "unless/end" do
      expect(render("unless false\n  <em>y</em>\nend")).to include("<em>y</em>")
    end

    it "case/when/else/end" do
      html = render("case \"b\"\nwhen \"a\"\n  <b>A</b>\nwhen \"b\"\n  <i>B</i>\nelse\n  <span>?</span>\nend")
      expect(html).to include("<i>B</i>")
    end

    it "begin/rescue/end" do
      expect(render("begin\n  <p>ok</p>\nrescue\n  <p>err</p>\nend")).to include("<p>ok</p>")
    end
  end

  describe "Ruby loops" do
    it ".each do |item| ... end" do
      html = render(<<~RSX, items: %w[a b]) { props :items }
        @items.each do |item|
          <li>{item}</li>
        end
      RSX
      expect(html).to include("a")
      expect(html).to include("b")
    end

    it ".each { |item| ... }" do
      html = render(<<~RSX, items: %w[x y]) { props :items }
        @items.each { |item|
          <li>{item}</li>
        }
      RSX
      expect(html).to include("x")
      expect(html).to include("y")
    end

    it ".times do |i| ... end" do
      html = render("2.times do |i|\n  <span>{i}</span>\nend")
      expect(html).to include("0")
      expect(html).to include("1")
    end

    it "while loop" do
      html = render(<<~RSX)
        @i = 0
        while @i < 2
          <span>{@i}</span>
          @i += 1
        end
      RSX
      expect(html).to include("0")
      expect(html).to include("1")
    end
  end

  describe "Ruby in tag bodies" do
    it "if/else inside a div" do
      html = render(<<~RSX, admin: true) { props :admin }
        <div>
          if @admin
            <b>Admin</b>
          else
            <i>User</i>
          end
        </div>
      RSX
      expect(html).to include("<b>Admin</b>")
    end

    it ".each inside a ul" do
      html = render(<<~RSX, items: %w[a b c]) { props :items }
        <ul>
          {@items.each do |item|
            <li>{item}</li>
          end}
        </ul>
      RSX
      expect(html).to include("<li>a</li>")
      expect(html).to include("<li>b</li>")
      expect(html).to include("<li>c</li>")
    end

    it "method call inside a tag" do
      html = render(<<~RSX)
        <div>
          {3.times do |i|
            <span>{i}</span>
          end}
        </div>
      RSX
      expect(html).to include("0")
      expect(html).to include("1")
      expect(html).to include("2")
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CORNER CASES — tricky inputs that break naive implementations
  # ═══════════════════════════════════════════════════════════════

  describe "string/comment safety" do
    it "ignores tags inside double-quoted strings" do
      result = preprocess('x = "<div>not a tag</div>"')
      expect(result).to include('"<div>not a tag</div>"')
      expect(result).not_to include("div do")
    end

    it "ignores tags inside single-quoted strings" do
      result = preprocess("x = '<div>not a tag</div>'")
      expect(result).not_to include("div do")
    end

    it "ignores tags inside heredocs" do
      result = preprocess(<<~'RUBY')
        x = <<~HTML
          <div>not a tag</div>
        HTML
      RUBY
      expect(result).to include("<<~HTML")
      expect(result).not_to include("div do")
    end

    it "ignores tags inside comments" do
      result = preprocess("# <div>not a tag</div>\n<p>real</p>")
      expect(result).to include("# <div>not a tag</div>")
      expect(result).to include("p do")
    end

    it "handles end-of-line comments" do
      result = preprocess("x = 1 # <div> not a tag\n<p>real</p>")
      expect(result).to include("# <div> not a tag")
      expect(result).to include("p do")
    end

    it "handles escaped quotes in strings" do
      result = preprocess('x = "she said \\"<div>\\" hi"')
      expect(result).not_to include("div do")
    end

    it "handles %q() strings" do
      result = preprocess('x = %q(<div>not a tag</div>)')
      expect(result).to include('%q(<div>not a tag</div>)')
      expect(result).not_to include("div do")
    end

    it "handles %Q() strings" do
      result = preprocess('x = %Q(<span>not a tag</span>)')
      expect(result).to include('%Q(<span>not a tag</span>)')
      expect(result).not_to include("span do")
    end

    it "handles %w() arrays" do
      result = preprocess('x = %w(hello world)')
      expect(result).to include('%w(hello world)')
    end

    it "handles %i[] symbol arrays" do
      result = preprocess('x = %i[foo bar]')
      expect(result).to include('%i[foo bar]')
    end

    it "handles backtick command strings" do
      result = preprocess('x = `echo <div>`')
      expect(result).to include('`echo <div>`')
      expect(result).not_to include("div do")
    end

    it "handles nested delimiters in percent-strings" do
      result = preprocess('x = %q(foo (bar) baz)')
      expect(result).to include('%q(foo (bar) baz)')
    end

    it "handles Regexp.new (safe alternative to // in .rsx)" do
      result = preprocess('x = Regexp.new("<div>")')
      expect(result).not_to include("div do")
    end
  end

  describe "arithmetic < operator" do
    it "does not treat < as tag in comparisons" do
      expect(preprocess("a < b")).to eq("a < b")
    end

    it "does not treat < as tag in chained comparisons" do
      expect(preprocess("a < b && c < d")).to include("a < b")
    end

    it "does not treat << as tag in shovel operator" do
      result = preprocess('arr << "item"')
      expect(result).to include("<<")
    end

    it "does not treat <= as tag" do
      expect(preprocess("a <= b")).to include("<=")
    end

    it "handles < followed by number" do
      expect(preprocess("x < 5")).to include("< 5")
    end
  end

  describe "HTML comments" do
    it "strips top-level HTML comments" do
      result = preprocess("<!-- TODO -->\n<div>x</div>")
      expect(result).not_to include("<!--")
      expect(result).to include("div do")
    end

    it "strips comments inside tag children" do
      html = render("<div><!-- hidden --><p>visible</p></div>")
      expect(html).not_to include("<!--")
      expect(html).to include("<p>visible</p>")
    end

    it "strips multi-line comments" do
      result = preprocess("<!--\n  multi\n  line\n-->\n<p>after</p>")
      expect(result).not_to include("multi")
      expect(result).to include("p do")
    end

    it "tracks line numbers through comments" do
      expect {
        preprocess("<!-- comment\nline 2\nline 3\n-->\n<div>x</span>")
      }.to raise_error(Grsx::SyntaxError, /line 5/)
    end
  end

  describe "multi-line attributes" do
    it "handles attributes spanning multiple lines" do
      result = preprocess("<div\n  class=\"foo\"\n  id=\"bar\"\n>x</div>")
      expect(result).to include('class: "foo"')
      expect(result).to include('id: "bar"')
    end

    it "renders multi-line attributes correctly" do
      html = render("<a\n  href=\"/about\"\n  class=\"link\"\n>About</a>")
      expect(html).to include('href="/about"')
      expect(html).to include('class="link"')
    end
  end

  describe "boolean attributes" do
    it "emits disabled: true for HTML elements" do
      result = preprocess('<input type="text" disabled />')
      expect(result).to include("disabled: true")
    end

    it "emits open: true for component props" do
      result = preprocess('<Modal open />')
      expect(result).to include("open: true")
    end
  end

  describe "multiple root elements" do
    it "renders multiple roots without a fragment wrapper" do
      html = render("<h1>Title</h1>\n<p>Body</p>")
      expect(html).to include("<h1>Title</h1>")
      expect(html).to include("<p>Body</p>")
    end
  end

  describe "whitespace handling" do
    it "preserves inline text in leaf elements" do
      html = render("<p>hello world</p>")
      expect(html).to include("hello world")
    end

    it "does not emit whitespace-only text between tags" do
      result = preprocess("<div>\n  <p>x</p>\n</div>")
      expect(result).not_to include('plain("\n')
      expect(result).not_to include('plain("  ")')
    end

    it "handles tags touching (no space): <b>a</b><i>b</i>" do
      html = render("<b>a</b><i>b</i>")
      expect(html).to include("a")
      expect(html).to include("b")
    end
  end

  describe "multi-line tags" do
    it "parses attributes across multiple lines" do
      html = render(<<~RSX)
        <div
          class="c"
          id="i">
          <p>x</p>
        </div>
      RSX
      expect(html).to include('class="c"')
      expect(html).to include('id="i"')
      expect(html).to include("x")
    end

    it "parses self-closing tag with multi-line attrs" do
      html = render(<<~RSX)
        <input
          type="text"
          name="q"
        />
      RSX
      expect(html).to include('type="text"')
      expect(html).to include('name="q"')
    end
  end

  describe "JSX convention corrections" do
    it "auto-corrects className to class" do
      result = preprocess('<div className="foo">x</div>')
      expect(result).to include('class: "foo"')
      expect(result).not_to include("className")
    end

    it "auto-corrects htmlFor to for" do
      result = preprocess('<label htmlFor="email">x</label>')
      expect(result).to include('for: "email"')
    end

    it "auto-corrects tabIndex to tabindex" do
      result = preprocess('<input tabIndex={0} />')
      expect(result).to include("tabindex: 0")
    end

    it "leaves standard HTML attributes unchanged" do
      result = preprocess('<div class="bar" id="x">y</div>')
      expect(result).to include('class: "bar"')
      expect(result).to include('id: "x"')
    end
  end

  describe "deep nesting" do
    it "handles 6 levels deep" do
      html = render("<div><section><article><header><h1><span>deep</span></h1></header></article></section></div>")
      expect(html).to include("<span>deep</span>")
      expect(html).to include("<div>")
      expect(html).to include("</div>")
    end
  end

  describe "adjacent text and expressions" do
    it "renders text before and after expression: <p>A {x} B</p>" do
      html = render('<p>A {"M"} B</p>')
      expect(html).to include("A")
      expect(html).to include("M")
      expect(html).to include("B")
    end

    it "renders multiple adjacent expressions" do
      html = render('<p>{"a"}{"b"}{"c"}</p>')
      expect(html).to include("a")
      expect(html).to include("b")
      expect(html).to include("c")
    end

    it "renders expression at start of text" do
      html = render('<p>{"X"} tail</p>')
      expect(html).to include("X")
      expect(html).to include("tail")
    end

    it "renders expression at end of text" do
      html = render('<p>start {"X"}</p>')
      expect(html).to include("X")
    end
  end

  describe "error messages" do
    it "raises Grsx::SyntaxError for mismatched tags" do
      expect { preprocess("<div>x</span>") }.to raise_error(Grsx::SyntaxError)
    end

    it "includes line number in mismatched tag error" do
      expect { preprocess("<div>x</span>") }.to raise_error(Grsx::SyntaxError, /line/)
    end

    it "names both expected and actual tags in mismatch error" do
      expect { preprocess("<div>x</span>") }.to raise_error(Grsx::SyntaxError, /expected.*div.*got.*span/i)
    end

    it "raises Grsx::SyntaxError for unclosed tag at EOF" do
      expect { preprocess("<div><p>x</p>") }.to raise_error(Grsx::SyntaxError, /unclosed/i)
    end

    it "includes opening line number in unclosed tag error" do
      expect { preprocess("<div><p>x</p>") }.to raise_error(Grsx::SyntaxError, /line 1/)
    end

    it "tracks correct line for multi-line unclosed tag" do
      source = "x = 1\ny = 2\n<div>\n<p>ok</p>"
      expect { preprocess(source) }.to raise_error(Grsx::SyntaxError, /line 3/)
    end

    it "raises Grsx::SyntaxError for unclosed fragment" do
      expect { preprocess("<><p>x</p>") }.to raise_error(Grsx::SyntaxError, /unclosed.*fragment/i)
    end

    it "raises Grsx::SyntaxError for unknown lowercase tags" do
      expect { preprocess("<dvi>x</dvi>") }.to raise_error(Grsx::SyntaxError, /unknown element.*dvi/i)
    end

    it "includes 'did you mean?' for typos" do
      expect { preprocess("<sectin>x</sectin>") }.to raise_error(Grsx::SyntaxError, /did you mean.*section/i)
    end

    it "includes component capitalization hint" do
      expect { preprocess("<custom>x</custom>") }.to raise_error(Grsx::SyntaxError, /components must start with uppercase/i)
    end

    it "exposes rsx_line on the error object" do
      begin
        preprocess("<div>x</span>")
      rescue Grsx::SyntaxError => e
        expect(e.rsx_line).to eq(1)
      end
    end

    it "includes source line context in error messages" do
      begin
        preprocess("<div>\n  <p>ok</p>\n  <dvi>bad</dvi>\n</div>")
      rescue Grsx::SyntaxError => e
        expect(e.message).to include("> 3 |")
        expect(e.message).to include("<dvi>")
      end
    end

    it "exposes source_context method" do
      begin
        preprocess("<p>ok</p>\n<dvi>bad</dvi>")
      rescue Grsx::SyntaxError => e
        expect(e.source_context).to include("> 2 |")
      end
    end
  end

  describe "compiled_template_code" do
    it "returns compiled Phlex DSL for inline templates" do
      klass = Class.new(Grsx::PhlexComponent) {
        template '<div class="card"><p>hello</p></div>'
      }
      code = klass.compiled_template_code
      expect(code).to include('div(class: "card")')
      expect(code).to include("p do")
    end
  end

  describe "pure Ruby passthrough" do
    it "passes simple assignment through unchanged" do
      ruby = "x = 1 + 2\n"
      expect(preprocess(ruby)).to eq(ruby)
    end

    it "passes method definitions through unchanged" do
      ruby = "def foo\n  42\nend\n"
      expect(preprocess(ruby)).to eq(ruby)
    end

    it "passes class definitions through unchanged" do
      ruby = "class Foo\n  def bar; end\nend\n"
      expect(preprocess(ruby)).to eq(ruby)
    end

    it "passes array/hash literals through unchanged" do
      ruby = "a = [1, 2, 3]\nh = { a: 1 }\n"
      expect(preprocess(ruby)).to eq(ruby)
    end

    it "passes empty string through" do
      expect(preprocess("")).to eq("")
    end

    it "passes whitespace-only string through" do
      expect(preprocess("  \n  \n")).to eq("  \n  \n")
    end
  end

  describe "complex attribute expressions" do
    it "ternary in attribute: class={x ? 'a' : 'b'}" do
      html = render('<div class={@x ? "a" : "b"}>y</div>', x: true) { props :x }
      expect(html).to include('class="a"')
    end

    it "method chain in attribute" do
      html = render('<p class={["a", "b"].join(" ")}>z</p>')
      expect(html).to include('class="a b"')
    end

    it "array class shorthand" do
      result = preprocess('<p class={["x", "y"]}>z</p>')
      expect(result).to include('class: ["x", "y"]')
    end

    it "string interpolation in attribute" do
      html = render('<p class={"item-#{@n}"}>z</p>', n: 5) { props :n }
      expect(html).to include("item-5")
    end
  end

  describe "component edge cases" do
    it "component inside component" do
      stub_const("OuterComponent", Class.new(Grsx::PhlexComponent) {
        template '<section>{content}</section>'
      })
      stub_const("InnerComponent", Class.new(Grsx::PhlexComponent) {
        template "<em>inner</em>"
      })
      html = render("<Outer><Inner /></Outer>")
      expect(html).to include("<section>")
      expect(html).to include("<em>inner</em>")
    end

    it "component with boolean prop" do
      stub_const("FlagComponent", Class.new(Grsx::PhlexComponent) {
        props :active
        template '<span>{@active.to_s}</span>'
      })
      html = render("<Flag active />")
      expect(html).to include("true")
    end

    it "component with no props or children" do
      stub_const("EmptyComponent", Class.new(Grsx::PhlexComponent) {
        template "<hr />"
      })
      html = render("<Empty />")
      expect(html).to include("<hr>")
    end
  end

  describe "curly brace disambiguation" do
    it "{ after .each is a Ruby block, not interpolation" do
      html = render(<<~RSX, items: %w[a]) { props :items }
        @items.each { |item|
          <span>{item}</span>
        }
      RSX
      expect(html).to include("a")
    end

    it "{ after .map is a Ruby block" do
      html = render(<<~RSX)
        [1, 2].each { |n|
          <span>{n}</span>
        }
      RSX
      expect(html).to include("1")
      expect(html).to include("2")
    end

    it "{ at start of line after > is text interpolation" do
      html = render("<p>{42}</p>")
      expect(html).to include("42")
    end
  end

  describe "text vs Ruby heuristic" do
    it "treats 'Hello World' as text" do
      html = render("<p>Hello World</p>")
      expect(html).to include("Hello World")
    end

    it "treats 'Click here!' as text" do
      html = render("<p>Click here!</p>")
      expect(html).to include("Click here!")
    end

  end

  describe "mixed content patterns" do
    it "text + tag siblings" do
      html = render("<div>before <b>bold</b> after</div>")
      expect(html).to include("before ")
      expect(html).to include("<b>bold</b>")
      expect(html).to include(" after")
    end

    it "multiple sibling tags with text preserves spaces" do
      html = render("<div><b>a</b> and <i>b</i></div>")
      expect(html).to include("<b>a</b> and <i>b</i>")
    end

    it "no-space siblings don't get spurious spaces" do
      html = render("<div><b>a</b><i>b</i></div>")
      expect(html).to include("<b>a</b><i>b</i>")
    end

    it "text + expression preserves trailing space" do
      html = render('<p>Hello {@name}!</p>', name: "World") { props :name }
      expect(html).to include("Hello World!")
    end

    it "expression + text + expression preserves spaces" do
      html = render('<p>{@a} + {@b}</p>', a: 1, b: 2) { props :a, :b }
      expect(html).to include("1 + 2")
    end

    it "expression + space + tag preserves space" do
      html = render('<p>{@x} <b>y</b></p>', x: "a") { props :x }
      expect(html).to include("a")
      expect(html).to include("<b>y</b>")
    end

    it "Ruby + tags + text in same parent" do
      html = render(<<~RSX, show: true) { props :show }
        <div>
          <h1>Title</h1>
          if @show
            <p>shown</p>
          end
        </div>
      RSX
      expect(html).to include("<h1>Title</h1>")
      expect(html).to include("<p>shown</p>")
    end
  end

  describe "Grsx.compile integration" do
    it "Grsx.compile uses the preprocessor" do
      html = Grsx.compile("<p>hello</p>")
      expect(html).to include("p do")
      expect(html).to include('plain("hello")')
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ADVANCED EDGE CASES — patterns from real-world usage
  # ═══════════════════════════════════════════════════════════════

  describe "namespaced components" do
    it "resolves Dot.Separated as namespaced component" do
      result = preprocess("<Admin.Button />")
      expect(result).to include('__resolve_rsx_const("Admin::Button")')
    end

    it "resolves deeply nested namespace" do
      result = preprocess("<UI.Forms.Input />")
      expect(result).to include('__resolve_rsx_const("UI::Forms::Input")')
    end
  end

  describe "conditional class patterns" do
    it "assembles class from ternary" do
      html = render('<p class={@active ? "active" : "inactive"}>x</p>', active: true) { props :active }
      expect(html).to include('class="active"')
    end

    it "handles nil class gracefully" do
      html = render('<p class={nil}>x</p>')
      expect(html).to include("<p>")
    end
  end

  describe "multiple splat attributes" do
    it "merges two splats" do
      result = preprocess('<div {**@a} {**@b}>x</div>')
      expect(result).to include("**@a")
      expect(result).to include("**@b")
    end

    it "mixes splat with named attrs" do
      result = preprocess('<div class="x" {**@extra}>y</div>')
      expect(result).to include('class: "x"')
      expect(result).to include("**@extra")
    end
  end

  describe "component with Ruby in body" do
    it "passes Ruby control flow to component children" do
      stub_const("WrapComponent", Class.new(Grsx::PhlexComponent) {
        template '<section>{content}</section>'
      })
      html = render(<<~RSX, show: true) { props :show }
        <Wrap>
          if @show
            <p>visible</p>
          end
        </Wrap>
      RSX
      expect(html).to include("<section>")
      expect(html).to include("<p>visible</p>")
    end
  end

  describe "nested components with passed props" do
    it "passes dynamic props through multiple levels" do
      stub_const("LabelComponent", Class.new(Grsx::PhlexComponent) {
        props :text
        template '<span class="label">{@text}</span>'
      })
      stub_const("CardComponent", Class.new(Grsx::PhlexComponent) {
        props :title
        template '<div class="card"><Label text={@title} /></div>'
      })
      html = render('<Card title="Hello" />')
      expect(html).to include("Hello")
      expect(html).to include('class="label"')
      expect(html).to include('class="card"')
    end
  end

  describe "tags after Ruby expressions" do
    it "handles tag after ternary on same line" do
      html = render(<<~RSX)
        @x = true ? "yes" : "no"
        <p>{@x}</p>
      RSX
      expect(html).to include("yes")
    end

    it "handles tag after method call" do
      html = render(<<~RSX)
        @items = [1, 2, 3]
        <p>{@items.length}</p>
      RSX
      expect(html).to include("3")
    end
  end

  describe "self-closing tags in loops" do
    it "renders void elements inside each" do
      html = render(<<~RSX)
        3.times do |i|
          <br />
        end
      RSX
      expect(html.scan("<br>").length).to eq(3)
    end

    it "renders self-closing components in a loop" do
      stub_const("DotComponent", Class.new(Grsx::PhlexComponent) {
        template "<hr />"
      })
      html = render(<<~RSX)
        2.times do |i|
          <Dot />
        end
      RSX
      expect(html.scan("<hr>").length).to eq(2)
    end
  end

  describe "tag with only expression children" do
    it "renders a tag with only {expr} inside" do
      html = render('<p>{"hello"}</p>')
      expect(html).to eq("<p>hello</p>")
    end

    it "renders a tag with multiple {expr} only" do
      html = render('<p>{"a"}{"b"}</p>')
      expect(html).to include("a")
      expect(html).to include("b")
    end
  end

  describe "empty and whitespace-only edge cases" do
    it "handles empty source" do
      expect(preprocess("")).to eq("")
    end

    it "handles whitespace-only source" do
      expect(preprocess("   \n  \n")).to eq("   \n  \n")
    end

    it "handles tag with only whitespace body" do
      html = render("<div>   </div>")
      expect(html).to include("<div>")
    end

    it "handles empty fragment" do
      result = preprocess("<></>")
      expect(result).to be_a(String)
    end
  end

  describe "heredoc followed by tag" do
    it "does not bleed heredoc into tag parsing" do
      html = render(<<~'RSX')
        @text = <<~TXT
          some content
        TXT
        <p>{@text.strip}</p>
      RSX
      expect(html).to include("some content")
    end
  end

  describe "deeply nested Ruby in tag body" do
    it "handles if inside each inside div" do
      html = render(<<~RSX, items: [1, 2, 3]) { props :items }
        <div>
          {@items.each do |n|
            if n.odd?
              <b>{n}</b>
            else
              <i>{n}</i>
            end
          end}
        </div>
      RSX
      expect(html).to include("<b>1</b>")
      expect(html).to include("<i>2</i>")
      expect(html).to include("<b>3</b>")
    end
  end

  describe "SVG support" do
    it "renders svg with circle" do
      html = render('<svg width="100" height="100"><circle cx="50" cy="50" r="40" /></svg>')
      expect(html).to include("<svg")
      expect(html).to include("<circle")
      expect(html).to include('cx="50"')
    end

    it "renders svg with path" do
      html = render('<svg viewBox="0 0 24 24"><path d="M12 2" stroke="black" /></svg>')
      expect(html).to include("<path")
      expect(html).to include('d="M12 2"')
    end

    it "renders nested g groups with children" do
      html = render('<svg><g transform="t(10)"><rect width="50" /><circle r="10" /></g></svg>')
      expect(html).to include("<g")
      expect(html).to include("<rect")
      expect(html).to include("<circle")
    end

    it "renders svg inside a div" do
      html = render('<div><svg width="24"><path d="M0 0" /></svg></div>')
      expect(html).to include("<div>")
      expect(html).to include("<svg")
      expect(html).to include("</svg>")
    end

    it "exits svg context correctly" do
      html = render('<svg><circle r="5" /></svg><div>after</div>')
      expect(html).to include("<circle")
      expect(html).to include("<div>after</div>")
    end
  end

  describe "stress test" do
    it "renders 50 items without stack overflow or crash" do
      html = render(<<~RSX, items: (1..50).to_a) { props :items }
        <ul>
          {@items.each do |n|
            <li>{n}</li>
          end}
        </ul>
      RSX
      expect(html.scan("<li>").length).to eq(50)
      expect(html).to include("<li>1</li>")
      expect(html).to include("<li>50</li>")
    end
  end
end
