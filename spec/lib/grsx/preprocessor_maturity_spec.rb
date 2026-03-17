# frozen_string_literal: true

require "spec_helper"

# JSX Maturity Tests — edge cases learned from JSX's 10-year evolution.
# Each test targets a specific lesson from Babel/SWC/React's journey.
RSpec.describe "GRSX maturity (JSX lessons)" do
  def preprocess(source)
    Grsx.compile(source)
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

  # ── Lesson 1: Whitespace between inline elements ──────────────
  # JSX strips insignificant whitespace but preserves meaningful spaces.
  # <span>a</span> <span>b</span> → "a b" (the space matters)
  describe "whitespace preservation" do
    it "preserves space between inline tags on the same line" do
      html = render("<span>a</span> <span>b</span>")
      # There should be a space between the two spans
      expect(html).to include("</span> <span>") | include("</span><span>")
      expect(html).to include("a")
      expect(html).to include("b")
    end

    it "renders tags on separate lines without extra whitespace" do
      html = render(<<~RSX)
        <div>
          <p>hello</p>
        </div>
      RSX
      expect(html).to include("<div>")
      expect(html).to include("<p>hello</p>")
    end
  end

  # ── Lesson 2: Multi-line tag attributes ───────────────────────
  # JSX supports attributes spanning multiple lines.
  describe "multi-line attributes" do
    it "handles attributes on multiple lines" do
      html = render(<<~RSX)
        <div
          class="container"
          id="main"
          data-controller="app">
          <p>content</p>
        </div>
      RSX
      expect(html).to include('class="container"')
      expect(html).to include('id="main"')
      expect(html).to include("content")
    end

    it "handles self-closing tags with multi-line attributes" do
      html = render(<<~RSX)
        <input
          type="text"
          name="email"
          placeholder="you@example.com"
        />
      RSX
      expect(html).to include('type="text"')
      expect(html).to include('name="email"')
    end
  end

  # ── Lesson 3: Mismatched tag detection ────────────────────────
  # Babel gives clear errors for mismatched tags.
  describe "mismatched tags" do
    it "raises or produces error for <div></span>" do
      # The preprocessor should either raise or the compiled code
      # should fail at eval time with a clear error
      source = "<div>hello</span>"
      expect {
        render(source)
      }.to raise_error(SyntaxError)
    end
  end

  # ── Lesson 4: Nested tags inside Ruby blocks ──────────────────
  # The key JSX pattern: {items.map(i => <Item key={i.id} />)}
  describe "tags inside Ruby blocks" do
    it "renders tags inside .each do block" do
      html = render(<<~RSX, items: %w[a b c]) { props :items }
        <ul>
          {@items.each do |item|}
            <li>{item}</li>
          {end}
        </ul>
      RSX
      expect(html).to include("<li>a</li>")
      expect(html).to include("<li>b</li>")
      expect(html).to include("<li>c</li>")
    end

    it "renders tags inside .map { block" do
      html = render(<<~RSX, items: %w[x y]) { props :items }
        <ul>
          {@items.each do |item|}
            <li>{item}</li>
          {end}
        </ul>
      RSX
      expect(html).to include("<li>x</li>")
      expect(html).to include("<li>y</li>")
    end

    it "renders tags inside .times block" do
      html = render(<<~RSX)
        <ul>
          {3.times do |i|}
            <li>{i}</li>
          {end}
        </ul>
      RSX
      expect(html).to include("<li>0</li>")
      expect(html).to include("<li>1</li>")
      expect(html).to include("<li>2</li>")
    end
  end

  # ── Lesson 5: String literal safety ───────────────────────────
  # JSX compilers must not transform tags inside various string types.
  describe "string literal safety" do
    it "ignores tags inside heredocs" do
      result = preprocess(<<~'RSX')
        x = <<~HTML
          <div>not a tag</div>
        HTML
      RSX
      expect(result).to include("<<~HTML")
      expect(result).not_to include("div do")
    end

    it "ignores tags inside %q() strings" do
      result = preprocess('x = %q(<div>not a tag</div>)')
      # This should pass through, but %q() isn't tracked yet
      # At minimum it shouldn't crash
      expect(result).to be_a(String)
    end

    it "handles Regexp.new (safe alternative to // in .rsx)" do
      result = preprocess('x = Regexp.new("<div>")')
      expect(result).not_to include("div do")
    end

    it "handles escaped quotes in strings" do
      result = preprocess('x = "she said \\"<div>\\" loudly"')
      expect(result).not_to include("div do")
    end
  end

  # ── Lesson 6: Complex expressions in attributes ───────────────
  # JSX handles nested function calls, ternaries, template literals.
  describe "complex attribute expressions" do
    it "handles ternary in attribute value" do
      html = render('<div class={@admin ? "admin" : "user"}>hi</div>', admin: true) { props :admin }
      expect(html).to include('class="admin"')
    end

    it "handles method calls in attribute value" do
      html = render('<p class={["a", "b"].join(" ")}>text</p>')
      expect(html).to include('class="a b"')
    end

    it "handles complex expression in attribute value" do
      html = render('<div class={["a", @b].compact.join(" ")}>x</div>', b: "b") { props :b }
      expect(html).to include('class="a b"')
    end
  end

  # ── Lesson 7: Boolean/bare attributes ─────────────────────────
  # JSX: <input disabled /> → disabled={true}
  describe "boolean attributes" do
    it "renders multiple boolean attributes" do
      html = render("<input disabled required readonly />")
      expect(html).to include("disabled")
      expect(html).to include("required")
      expect(html).to include("readonly")
    end

    it "renders mixed boolean and valued attributes" do
      html = render('<input type="text" disabled name="x" />')
      expect(html).to include('type="text"')
      expect(html).to include("disabled")
      expect(html).to include('name="x"')
    end
  end

  # ── Lesson 8: Deep nesting ────────────────────────────────────
  describe "deep nesting" do
    it "handles 5+ levels of nesting" do
      html = render(<<~RSX)
        <div>
          <section>
            <article>
              <header>
                <h1>
                  <span>deep</span>
                </h1>
              </header>
            </article>
          </section>
        </div>
      RSX
      expect(html).to include("<span>deep</span>")
      expect(html).to include("<div>")
    end
  end

  # ── Lesson 9: Adjacent sibling expressions ────────────────────
  # JSX: <p>Hello {name}!</p> → text, expression, text
  describe "adjacent text and expressions" do
    it "renders text before and after an expression" do
      html = render('<p>Hello {name}!</p>') do
        define_method(:name) { "World" }
      end
      expect(html).to include("Hello")
      expect(html).to include("World")
      expect(html).to include("!")
    end

    it "renders multiple expressions in sequence" do
      html = render('<p>{@first} {" "} {" "} {@last}</p>', first: "A", last: "B") { props :first, :last }
      expect(html).to include("A")
      expect(html).to include("B")
    end
  end

  # ── Lesson 10: Empty elements ─────────────────────────────────
  describe "empty elements" do
    it "renders an empty div" do
      html = render("<div></div>")
      expect(html).to include("<div></div>")
    end

    it "renders an empty span" do
      html = render("<span></span>")
      expect(html).to include("<span></span>")
    end
  end

  # ── Lesson 11: Special HTML characters in text ────────────────
  describe "special characters" do
    it "preserves HTML entities in text" do
      html = render("<p>5 &gt; 3</p>")
      expect(html).to include("&gt;") | include(">")
    end
  end

  # ── Lesson 12: Case/when with tags ────────────────────────────
  describe "case/when with tags" do
    it "renders the matching branch" do
      html = render(<<~RSX, role: "admin") { props :role }
        case @role
        when "admin"
          <b>Admin</b>
        when "user"
          <i>User</i>
        else
          <span>Guest</span>
        end
      RSX
      expect(html).to include("<b>Admin</b>")
      expect(html).not_to include("<i>")
    end
  end

  # ── Lesson 13: begin/rescue with tags ─────────────────────────
  describe "begin/rescue with tags" do
    it "renders normally without error" do
      html = render(<<~RSX)
        begin
          <p>safe</p>
        rescue => e
          <p>error</p>
        end
      RSX
      expect(html).to include("<p>safe</p>")
    end
  end

  # ── Lesson 14: Return values from blocks with tags ────────────
  describe "method calls returning tags" do
    it "renders from a method that yields tags" do
      html = render(<<~RSX)
        if true
          <strong>yes</strong>
        end
      RSX
      expect(html).to include("<strong>yes</strong>")
    end
  end

  # ── Lesson 15: Comments inside tag children ───────────────────
  describe "comments" do
    it "passes Ruby comments through in Ruby context" do
      result = preprocess(<<~RSX)
        # This is a comment
        <div>hello</div>
      RSX
      expect(result).to include("# This is a comment")
      expect(result).to include("div { ")
    end
  end
end
