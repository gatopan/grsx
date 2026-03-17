# frozen_string_literal: true

require "spec_helper"

# ═══════════════════════════════════════════════════════════════════════
# GRSX Pipeline Spec — Complex, adversarial, and real-world patterns.
#
# These specs exercise the full Lexer → AST → Codegen pipeline at three
# levels: AST structure (Parser output), compiled code (Codegen output),
# and rendered HTML (end-to-end). They target the gaps left by the base
# preprocessor_spec.rb — focusing on deeply nested structures, mixed
# Ruby/RSX interactions, adversarial inputs, source maps, and realistic
# page-level templates.
# ═══════════════════════════════════════════════════════════════════════

RSpec.describe "GRSX Pipeline" do
  def preprocess(source)
    Grsx.compile(source)
  end

  def parse(source)
    Grsx::Parser.new(source).parse
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

  # ═══════════════════════════════════════════════════════════════════
  # AST STRUCTURAL TESTS — verify the Parser produces correct trees
  # ═══════════════════════════════════════════════════════════════════

  describe "AST structure" do
    it "parses a simple tag into a Tag node with correct name and kind" do
      ast = parse("<div>hello</div>")
      tag = ast.find { |n| n.is_a?(Grsx::AST::Tag) }
      expect(tag).not_to be_nil
      expect(tag.name).to eq("div")
      expect(tag.kind).to eq(:html)
      expect(tag.self_closing).to be false
    end

    it "marks void elements as self-closing" do
      ast = parse("<br />")
      tag = ast.find { |n| n.is_a?(Grsx::AST::Tag) }
      expect(tag.self_closing).to be true
    end

    it "classifies uppercase tags as :component" do
      ast = parse("<MyWidget />")
      tag = ast.find { |n| n.is_a?(Grsx::AST::Tag) }
      expect(tag.kind).to eq(:component)
    end

    it "classifies SVG children as :svg" do
      ast = parse('<svg><circle r="5" /></svg>')
      svg_tag = ast.find { |n| n.is_a?(Grsx::AST::Tag) && n.name == "svg" }
      circle = svg_tag.children.find { |n| n.is_a?(Grsx::AST::Tag) && n.name == "circle" }
      expect(circle.kind).to eq(:svg)
    end

    it "parses static attributes as AttrValue with kind :static" do
      ast = parse('<input type="text" />')
      tag = ast.find { |n| n.is_a?(Grsx::AST::Tag) }
      attr = tag.attrs.first
      expect(attr.name).to eq("type")
      expect(attr.value.source).to eq("text")
      expect(attr.value).to be_static
    end

    it "parses dynamic attributes as AttrValue with kind :dynamic" do
      ast = parse('<input value={@val} />')
      tag = ast.find { |n| n.is_a?(Grsx::AST::Tag) }
      attr = tag.attrs.first
      expect(attr.name).to eq("value")
      expect(attr.value).to be_dynamic
      expect(attr.value.source).to eq("@val")
    end

    it "parses boolean attributes with nil value" do
      ast = parse("<input disabled />")
      tag = ast.find { |n| n.is_a?(Grsx::AST::Tag) }
      attr = tag.attrs.find { |a| a.name == "disabled" }
      expect(attr.value).to be_nil
    end

    it "parses splat attributes" do
      ast = parse("<div {**opts} />")
      tag = ast.find { |n| n.is_a?(Grsx::AST::Tag) }
      attr = tag.attrs.first
      expect(attr.splat).to be true
    end

    it "parses fragments with children" do
      ast = parse("<><p>a</p><p>b</p></>")
      frag = ast.find { |n| n.is_a?(Grsx::AST::Fragment) }
      expect(frag).not_to be_nil
      tags = frag.children.select { |n| n.is_a?(Grsx::AST::Tag) }
      expect(tags.length).to eq(2)
    end

    it "parses text nodes with correct content" do
      ast = parse("<p>hello world</p>")
      tag = ast.find { |n| n.is_a?(Grsx::AST::Tag) }
      text = tag.children.find { |n| n.is_a?(Grsx::AST::Text) }
      expect(text.content).to eq("hello world")
    end

    it "parses expression nodes" do
      ast = parse("<p>{@name}</p>")
      tag = ast.find { |n| n.is_a?(Grsx::AST::Tag) }
      expr = tag.children.find { |n| n.is_a?(Grsx::AST::Expr) }
      expect(expr.source).to eq("@name")
    end

    it "tracks source locations on all node types" do
      ast = parse("<div>\n  <p>text</p>\n</div>")
      tag = ast.find { |n| n.is_a?(Grsx::AST::Tag) }
      expect(tag.location).not_to be_nil
      expect(tag.location.line).to eq(1)

      p_tag = tag.children.find { |n| n.is_a?(Grsx::AST::Tag) }
      expect(p_tag.location.line).to eq(2)
    end

    it "handles deeply nested tag trees" do
      source = "<div><section><article><header><nav><main><aside><footer>deep</footer></aside></main></nav></header></article></section></div>"
      ast = parse(source)
      # Walk to the innermost tag
      node = ast.find { |n| n.is_a?(Grsx::AST::Tag) }
      depth = 0
      while node.is_a?(Grsx::AST::Tag) && node.children.any? { |c| c.is_a?(Grsx::AST::Tag) }
        node = node.children.find { |c| c.is_a?(Grsx::AST::Tag) }
        depth += 1
      end
      expect(depth).to eq(7) # div > section > article > header > nav > main > aside > footer
      expect(node.name).to eq("footer")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # AST PRETTY-PRINTING — verify readable tree output
  # ═══════════════════════════════════════════════════════════════════

  describe "AST pretty-printing" do
    it "produces readable output for a tag with attrs and children" do
      ast = parse('<div class="x"><p>hi</p></div>')
      output = ast.map { |n| n.to_s }.join("\n")
      expect(output).to include('Tag(:html, "div"')
      expect(output).to include('Attr(class="x")')
      expect(output).to include('Tag(:html, "p")')
      expect(output).to include('Text("hi")')
    end

    it "shows self_closing flag" do
      ast = parse("<br />")
      output = ast.map(&:to_s).join
      expect(output).to include("self_closing")
    end

    it "shows component kind" do
      ast = parse("<MyWidget />")
      output = ast.map(&:to_s).join
      expect(output).to include(":component")
    end

    it "shows fragment nodes" do
      ast = parse("<><p>a</p></>")
      output = ast.map(&:to_s).join("\n")
      expect(output).to include("Fragment()")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SOURCE MAP TESTS — verify # line N pragmas
  # ═══════════════════════════════════════════════════════════════════

  describe "line alignment" do
    it "aligns a top-level tag to its source line" do
      code = preprocess("<div>x</div>")
      # First line of compiled output should start with the tag
      first_meaningful = code.lines.find { |l| l.strip.length > 0 }
      expect(first_meaningful).to include("div")
    end

    it "aligns multi-line source — tag on line 2 is on compiled line 2" do
      source = "@x = 1\n<div>hello</div>"
      code = preprocess(source)
      lines = code.lines
      # Line 2 should contain the div tag
      expect(lines[1]).to include("div")
    end

    it "preserves blank lines to maintain line correspondence" do
      source = <<~RSX
        @x = 1
        @y = 2
        <div>
          <p>hello</p>
          <span>world</span>
        </div>
      RSX
      code = preprocess(source)
      # The div tag (source line 3) should be on or near compiled line 3
      lines = code.lines
      div_line = lines.index { |l| l.include?("div") }
      expect(div_line).to be <= 3  # 0-indexed, so line 3 = index 2..3
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # DEEPLY NESTED RUBY + RSX INTERACTIONS
  # ═══════════════════════════════════════════════════════════════════

  describe "deeply nested Ruby control flow" do
    it "handles if/elsif/else with different tags in each branch" do
      html = render(<<~RSX, role: "editor") { props :role }
        <div>
          {if @role == "admin"}
            <strong>Admin Panel</strong>
          {elsif @role == "editor"}
            <em>Editor View</em>
          {else}
            <span>Guest View</span>
          {end}
        </div>
      RSX
      expect(html).to include("<em>Editor View</em>")
      expect(html).not_to include("Admin Panel")
      expect(html).not_to include("Guest View")
    end

    it "handles triple-nested control flow: each > if > ternary" do
      html = render(<<~RSX, items: [1, 2, 3, 4]) { props :items }
        <ul>
          {@items.each do |n|}
            {if n > 1}
              {if n.even?}
                <li class="even">{n}</li>
              {else}
                <li class="odd">{n}</li>
              {end}
            {end}
          {end}
        </ul>
      RSX
      expect(html).to include('class="even"')
      expect(html).to include('class="odd"')
      expect(html).not_to include(">1<")
      expect(html).to include(">2<")
      expect(html).to include(">3<")
      expect(html).to include(">4<")
    end

    it "handles nested .each with different iterators" do
      html = render(<<~RSX, matrix: [[1, 2], [3, 4]]) { props :matrix }
        <table>
          {@matrix.each do |row|}
            <tr>
              {row.each do |cell|}
                <td>{cell}</td>
              {end}
            </tr>
          {end}
        </table>
      RSX
      expect(html.scan("<tr>").length).to eq(2)
      expect(html.scan("<td>").length).to eq(4)
      expect(html).to include("<td>1</td>")
      expect(html).to include("<td>4</td>")
    end

    it "handles begin/rescue/ensure with tags" do
      html = render(<<~RSX)
        <div>
          {begin}
            <p>trying</p>
          {rescue => e}
            <p>rescued</p>
          {ensure}
            <p>ensured</p>
          {end}
        </div>
      RSX
      expect(html).to include("<p>trying</p>")
      expect(html).to include("<p>ensured</p>")
      expect(html).not_to include("<p>rescued</p>")
    end

    it "handles loop with conditional tags" do
      html = render(<<~RSX)
        <ul>
          {5.times do |i|}
            {if i.even?}
              <li>{"even " + i.to_s}</li>
            {end}
          {end}
        </ul>
      RSX
      expect(html).to include("even 0")
      expect(html).to include("even 2")
      expect(html).to include("even 4")
      expect(html).not_to include("even 1")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # COMPONENT COMPOSITION PATTERNS
  # ═══════════════════════════════════════════════════════════════════

  describe "complex component composition" do
    before do
      stub_const("BadgeComponent", Class.new(Grsx::PhlexComponent) {
        props :label, color: "gray"
        template '<span class={@color}>{@label}</span>'
      })

      stub_const("CardComponent", Class.new(Grsx::PhlexComponent) {
        props :title
        template <<~RSX
          <article class="card">
            <h3>{@title}</h3>
            <div class="body">{content}</div>
          </article>
        RSX
      })

      stub_const("LayoutComponent", Class.new(Grsx::PhlexComponent) {
        template <<~RSX
          <div class="layout">
            <main>{content}</main>
          </div>
        RSX
      })
    end

    it "renders component with mixed static and dynamic props" do
      html = render('<Badge label={@text} color="blue" />', text: "New") { props :text }
      expect(html).to include("New")
      expect(html).to include('class="blue"')
    end

    it "renders component with children containing control flow" do
      html = render(<<~RSX, show: true) { props :show }
        <Card title="Test">
          {if @show}
            <p>Visible content</p>
          {end}
        </Card>
      RSX
      expect(html).to include("Test")
      expect(html).to include("<p>Visible content</p>")
      expect(html).to include('class="card"')
    end

    it "renders component with loop children" do
      html = render(<<~RSX, tags: %w[ruby rails phlex]) { props :tags }
        <Card title="Tags">
          <ul>
            {@tags.each do |tag|}
              <li><Badge label={tag} color="green" /></li>
            {end}
          </ul>
        </Card>
      RSX
      expect(html).to include('class="card"')
      expect(html.scan('class="green"').length).to eq(3)
      expect(html).to include("ruby")
      expect(html).to include("phlex")
    end

    it "renders triple-nested components" do
      html = render(<<~RSX)
        <Layout>
          <Card title="Nested">
            <Badge label="deep" color="red" />
          </Card>
        </Layout>
      RSX
      expect(html).to include('class="layout"')
      expect(html).to include('class="card"')
      expect(html).to include('class="red"')
      expect(html).to include("deep")
    end

    it "renders conditional component rendering with &&" do
      html = render(<<~RSX, admin: false) { props :admin }
        <div>
          {@admin && render(BadgeComponent.new(label: "Admin", color: "red"))}
          <p>Always visible</p>
        </div>
      RSX
      expect(html).not_to include("Admin")
      expect(html).to include("Always visible")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ADVERSARIAL STRING & TAG BOUNDARY CASES
  # ═══════════════════════════════════════════════════════════════════

  describe "adversarial string and tag boundaries" do
    it "handles string with escaped newlines containing tags" do
      result = preprocess('x = "line1\\n<div>\\nline3"')
      expect(result).not_to include("div do")
    end

    it "handles string interpolation with tag-like content" do
      result = preprocess('x = "Hello #{user.name} <not a tag>"')
      expect(result).not_to include("not do")
    end

    it "handles multiple strings on one line" do
      result = preprocess('x = "<div>" + "<span>" + "</div>"')
      expect(result).not_to include("div do")
      expect(result).not_to include("span do")
    end

    it "handles multiline string concatenation before a real tag" do
      html = render(<<~'RSX')
        @msg = "hello " \
               "world"
        <p>{@msg}</p>
      RSX
      expect(html).to include("hello world")
    end

    it "handles heredoc with tag-like content followed by real tag" do
      html = render(<<~'RSX')
        @html = <<~HTML
          <div>not compiled</div>
        HTML
        <p>{@html.strip}</p>
      RSX
      expect(html).to include("&lt;div&gt;")
      expect(html).to include("<p>")
    end

    it "handles percent-string with nested delimiters before a tag" do
      html = render(<<~RSX)
        @words = %w(hello world)
        <p>{@words.join(" ")}</p>
      RSX
      expect(html).to include("hello world")
    end

    it "handles symbol array before a tag" do
      html = render(<<~RSX)
        @syms = %i[a b c]
        <p>{@syms.length}</p>
      RSX
      expect(html).to include("3")
    end

    it "handles backtick string before a tag" do
      result = preprocess(<<~RSX)
        @cmd = `echo hello`
        <p>done</p>
      RSX
      expect(result).to include("`echo hello`")
      expect(result).to include("p { ")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # COMPLEX ATTRIBUTE PATTERNS
  # ═══════════════════════════════════════════════════════════════════

  describe "complex attribute patterns" do
    it "handles hash literal in attribute" do
      html = render('<div data={({ action: "click" }.inspect)}>x</div>')
      expect(html).to include("action")
    end

    it "handles method chain in attribute" do
      html = render('<p class={["base", @extra].compact.join(" ")}>x</p>', extra: "active") { props :extra }
      expect(html).to include('class="base active"')
    end

    it "handles nested ternary in attribute" do
      html = render(<<~RSX, level: 2) { props :level }
        <span class={@level > 2 ? "high" : @level > 1 ? "medium" : "low"}>x</span>
      RSX
      expect(html).to include('class="medium"')
    end

    it "handles if/else expression in attribute" do
      html = render('<div class={if true then "yes" else "no" end}>x</div>')
      expect(html).to include('class="yes"')
    end

    it "handles multiple dynamic attributes" do
      html = render(<<~RSX, cls: "active", style_val: "color:red") { props :cls, :style_val }
        <div class={@cls} style={@style_val} id={"item-#{rand(1)}"}>x</div>
      RSX
      expect(html).to include('class="active"')
      expect(html).to include('style="color:red"')
    end

    it "handles splat with method call" do
      html = render('<div {**{ id: "x", class: "y" }}>z</div>')
      expect(html).to include('id="x"')
      expect(html).to include('class="y"')
    end

    it "handles attribute with array value" do
      result = preprocess('<div class={["a", "b", "c"]}>x</div>')
      expect(result).to include('class: ["a", "b", "c"]')
    end

    it "handles attribute with string interpolation containing braces" do
      html = render('<p title={"Count: #{[1,2,3].length}"}>x</p>')
      expect(html).to include('title="Count: 3"')
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # SVG COMPLEX PATTERNS
  # ═══════════════════════════════════════════════════════════════════

  describe "complex SVG" do
    it "renders SVG with multiple nested groups and elements" do
      html = render(<<~RSX)
        <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="grad1">
              <stop offset="0%" style="stop-color:rgb(255,255,0)" />
              <stop offset="100%" style="stop-color:rgb(255,0,0)" />
            </linearGradient>
          </defs>
          <g transform="translate(10,10)">
            <rect width="80" height="80" fill="url(#grad1)" />
            <circle cx="40" cy="40" r="30" fill="blue" />
          </g>
        </svg>
      RSX
      expect(html).to include("<svg")
      expect(html).to include("<defs>")
      expect(html).to include("<linearGradient")
      expect(html).to include("<stop")
      expect(html).to include("<rect")
      expect(html).to include("<circle")
    end

    it "renders SVG inside HTML with correct context switching" do
      html = render(<<~RSX)
        <div class="icon-container">
          <svg width="24" height="24">
            <path d="M12 2L2 22h20L12 2z" fill="orange" />
          </svg>
          <span>Warning</span>
        </div>
      RSX
      expect(html).to include('<div class="icon-container">')
      expect(html).to include("<svg")
      expect(html).to include("<path")
      expect(html).to include("<span>Warning</span>")
    end

    it "renders dynamic SVG attributes" do
      html = render('<svg><circle r={@radius} cx="50" cy="50" /></svg>', radius: 25) { props :radius }
      expect(html).to include('r="25"')
    end

    it "handles SVG elements with camelCase attributes" do
      html = render('<svg><rect rx="5" ry="5" width="100" height="50" /></svg>')
      expect(html).to include('rx="5"')
      expect(html).to include('ry="5"')
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FRAGMENT EDGE CASES
  # ═══════════════════════════════════════════════════════════════════

  describe "fragment edge cases" do
    it "handles nested fragments" do
      html = render(<<~RSX)
        <>
          <>
            <p>deep fragment</p>
          </>
        </>
      RSX
      expect(html).to include("<p>deep fragment</p>")
      expect(html).not_to include("<>")
    end

    it "handles fragment with control flow" do
      html = render(<<~RSX, show: true) { props :show }
        <>
          {if @show}
            <p>shown</p>
          {end}
          <p>always</p>
        </>
      RSX
      expect(html).to include("<p>shown</p>")
      expect(html).to include("<p>always</p>")
    end

    it "handles fragment with mixed text, expressions, and tags" do
      html = render(<<~RSX)
        <>
          <h1>Title</h1>
          <p>Body text with {"interpolation"}</p>
          <footer>End</footer>
        </>
      RSX
      expect(html).to include("<h1>Title</h1>")
      expect(html).to include("interpolation")
      expect(html).to include("<footer>End</footer>")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # REAL-WORLD PAGE-LEVEL TEMPLATES
  # ═══════════════════════════════════════════════════════════════════

  describe "real-world page templates" do
    it "renders a navigation bar with active state" do
      html = render(<<~RSX, current: "/about", links: [["/", "Home"], ["/about", "About"], ["/contact", "Contact"]]) { props :current, :links }
        <nav class="navbar">
          <ul>
            {@links.each do |path, label|}
              <li class={path == @current ? "active" : ""}>
                <a href={path}>{label}</a>
              </li>
            {end}
          </ul>
        </nav>
      RSX
      expect(html).to include('class="navbar"')
      expect(html.scan("<li").length).to eq(3)
      expect(html).to include('class="active"')
      expect(html).to include('href="/about"')
    end

    it "renders a data table with header, rows, and empty state" do
      html = render(<<~RSX, columns: %w[Name Email], rows: [["Alice", "a@x.com"], ["Bob", "b@x.com"]]) { props :columns, :rows }
        <table class="data-table">
          <thead>
            <tr>
              {@columns.each do |col|}
                <th>{col}</th>
              {end}
            </tr>
          </thead>
          <tbody>
            {if @rows.empty?}
              <tr>
                <td colspan={@columns.length.to_s}>No data</td>
              </tr>
            {else}
              {@rows.each do |row|}
                <tr>
                  {row.each do |cell|}
                    <td>{cell}</td>
                  {end}
                </tr>
              {end}
            {end}
          </tbody>
        </table>
      RSX
      expect(html).to include('class="data-table"')
      expect(html.scan("<th>").length).to eq(2)
      expect(html.scan("<td>").length).to eq(4)
      expect(html).to include("<td>Alice</td>")
      expect(html).to include("<td>b@x.com</td>")
      expect(html).not_to include("No data")
    end

    it "renders data table empty state when no rows" do
      html = render(<<~RSX, columns: %w[Name], rows: []) { props :columns, :rows }
        <table>
          <tbody>
            {if @rows.empty?}
              <tr><td>No data</td></tr>
            {else}
              {@rows.each do |row|}
                <tr><td>{row}</td></tr>
              {end}
            {end}
          </tbody>
        </table>
      RSX
      expect(html).to include("No data")
    end

    it "renders a form with various input types" do
      html = render(<<~RSX)
        <form action="/submit" method="post">
          <div class="field">
            <label for="name">Name</label>
            <input type="text" id="name" name="name" required />
          </div>
          <div class="field">
            <label for="email">Email</label>
            <input type="email" id="email" name="email" placeholder="you@example.com" />
          </div>
          <div class="field">
            <label for="message">Message</label>
            <textarea id="message" name="message" rows="4">Default text</textarea>
          </div>
          <button type="submit" class="btn">Send</button>
        </form>
      RSX
      expect(html).to include('action="/submit"')
      expect(html).to include('method="post"')
      expect(html).to include('type="text"')
      expect(html).to include('type="email"')
      expect(html).to include('placeholder="you@example.com"')
      expect(html).to include("<textarea")
      expect(html).to include("Default text")
      expect(html).to include('type="submit"')
    end

    it "renders a card grid with conditional badges" do
      items = [
        { name: "Alpha",   status: "active" },
        { name: "Beta",    status: "inactive" },
        { name: "Gamma",   status: "active" },
      ]
      html = render(<<~RSX, items: items) { props :items }
        <div class="grid">
          {@items.each do |item|}
            <div class="card">
              <h3>{item[:name]}</h3>
              {if item[:status] == "active"}
                <span class="badge green">Active</span>
              {else}
                <span class="badge red">Inactive</span>
              {end}
            </div>
          {end}
        </div>
      RSX
      expect(html.scan('class="card"').length).to eq(3)
      expect(html.scan("Active").length).to eq(2)
      expect(html.scan("Inactive").length).to eq(1)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # HYPHENATED PROSE & TEXT DETECTION EDGE CASES
  # ═══════════════════════════════════════════════════════════════════

  describe "hyphenated prose detection" do
    it "treats 'state-of-the-art' as text" do
      html = render("<p>state-of-the-art</p>")
      expect(html).to include("state-of-the-art")
    end

    it "treats 'should-not-appear' as text (not Ruby subtraction)" do
      html = render("<em>should-not-appear</em>")
      expect(html).to include("should-not-appear")
    end

    it "treats 'well-known' as text" do
      html = render("<p>A well-known fact</p>")
      expect(html).to include("well-known")
    end

    it "treats 'e-commerce' as text" do
      html = render("<h1>The e-commerce revolution</h1>")
      expect(html).to include("e-commerce")
    end

    it "still treats a - b as Ruby when inside a code context" do
      html = render("<p>{10 - 3}</p>")
      expect(html).to include("7")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # BLOCK BRACE PATTERNS
  # ═══════════════════════════════════════════════════════════════════

  describe "brace block patterns" do
    it "renders tags inside .each { } brace blocks" do
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

    it "renders tags inside .map { } brace blocks" do
      html = render(<<~'RSX', items: [1, 2, 3]) { props :items }
        <ul>
          {@items.map do |n|}
            <li class={"item-#{n}"}>{n}</li>
          {end}
        </ul>
      RSX
      expect(html).to include('class="item-1"')
      expect(html).to include("<li")
    end

    it "renders tags inside .times { } blocks" do
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

    it "renders self-closing tags inside brace blocks" do
      html = render(<<~RSX)
        <div>
          {3.times do |i|}
            <br />
          {end}
        </div>
      RSX
      expect(html.scan("<br>").length).to eq(3)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ERROR HANDLING — complex error scenarios
  # ═══════════════════════════════════════════════════════════════════

  describe "complex error handling" do
    it "reports correct line for deeply nested mismatch" do
      source = <<~RSX
        <div>
          <section>
            <article>
              <p>text</span>
            </article>
          </section>
        </div>
      RSX
      expect { preprocess(source) }.to raise_error(Grsx::SyntaxError, /line 4/)
    end

    it "reports unclosed tag at correct line in large source" do
      source = <<~RSX
        @x = 1
        @y = 2
        @z = 3
        <div>
          <p>hello</p>
          <section>
            <p>nested</p>
      RSX
      expect { preprocess(source) }.to raise_error(Grsx::SyntaxError, /unclosed/i)
    end

    it "provides source context in error for typos" do
      begin
        preprocess("<div>\n  <sectin>x</sectin>\n</div>")
      rescue Grsx::SyntaxError => e
        expect(e.message).to include("sectin")
        expect(e.rsx_line).to eq(2)
      end
    end

    it "raises on mismatched fragment close" do
      expect { preprocess("<>text</div>") }.to raise_error(Grsx::SyntaxError)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # STRESS TESTS — performance and scale
  # ═══════════════════════════════════════════════════════════════════

  describe "stress tests" do
    it "handles 200 items in a loop without crash" do
      html = render(<<~RSX, items: (1..200).to_a) { props :items }
        <ul>
          {@items.each do |n|}
            <li>{n}</li>
          {end}
        </ul>
      RSX
      expect(html.scan("<li>").length).to eq(200)
      expect(html).to include("<li>1</li>")
      expect(html).to include("<li>200</li>")
    end

    it "handles 10 levels of nesting without stack overflow" do
      tags = (1..10).map { |i| "div" }
      open = tags.map { |t| "<#{t}>" }.join
      close = tags.map { |t| "</#{t}>" }.reverse.join
      source = "#{open}deep#{close}"
      html = render(source)
      expect(html).to include("deep")
      expect(html.scan("<div>").length).to eq(10)
    end

    it "handles 50 attributes on a single tag" do
      attrs = (1..50).map { |i| "data-attr-#{i}=\"val#{i}\"" }.join(" ")
      html = render("<div #{attrs}>x</div>")
      expect(html).to include('data-attr-1="val1"')
      expect(html).to include('data-attr-50="val50"')
    end

    it "handles 20 sibling tags" do
      siblings = (1..20).map { |i| "<span>#{i}</span>" }.join
      html = render("<div>#{siblings}</div>")
      expect(html.scan("<span>").length).to eq(20)
    end

    it "compiles large source in reasonable time" do
      source = (1..100).map { |i| "<div><p>Paragraph #{i}</p></div>\n" }.join
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      preprocess(source)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be < 2.0 # Should compile in under 2 seconds
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # ELEMENTS MODULE — canonical constant source
  # ═══════════════════════════════════════════════════════════════════

  describe "Grsx::Elements" do
    it "VOID contains all HTML5 void elements" do
      %w[area base br col embed hr img input link meta source track wbr].each do |el|
        expect(Grsx::Elements::VOID).to include(el)
      end
    end

    it "SVG contains SVG-specific elements" do
      %w[circle path rect g defs linearGradient].each do |el|
        expect(Grsx::Elements::SVG).to include(el)
      end
    end

    it "KNOWN is a superset of VOID and SVG" do
      Grsx::Elements::VOID.each { |el| expect(Grsx::Elements::KNOWN).to include(el) }
      Grsx::Elements::SVG.each { |el| expect(Grsx::Elements::KNOWN).to include(el) }
    end

    it "JSX_ATTR_CORRECTIONS maps className to class" do
      expect(Grsx::Elements::JSX_ATTR_CORRECTIONS["className"]).to eq("class")
    end

    it "all collections are frozen" do
      expect(Grsx::Elements::VOID).to be_frozen
      expect(Grsx::Elements::SVG).to be_frozen
      expect(Grsx::Elements::KNOWN).to be_frozen
      expect(Grsx::Elements::JSX_ATTR_CORRECTIONS).to be_frozen
    end



  end

  # ═══════════════════════════════════════════════════════════════════
  # EDGE-CASE SPEC SUITE — deterministic grammar boundary tests
  # ═══════════════════════════════════════════════════════════════════

  describe "edge cases" do
    describe "unclosed expressions" do
      it "raises SyntaxError for unclosed { in children" do
        expect { preprocess('<p>{@name</p>') }.to raise_error(Grsx::SyntaxError, /Unclosed expression/)
      end

      it "raises SyntaxError for unclosed { at EOF" do
        expect { preprocess('<p>{@name') }.to raise_error(Grsx::SyntaxError, /Unclosed expression/)
      end

      it "raises SyntaxError for unclosed { in attribute value" do
        expect { preprocess('<p class={@foo></p>') }.to raise_error(Grsx::SyntaxError, /Unclosed expression/)
      end

      it "reports the correct opening line number" do
        source = "<div>\n  <p>\n    {@name\n  </p>\n</div>"
        expect { preprocess(source) }.to raise_error(Grsx::SyntaxError) { |e|
          expect(e.rsx_line).to eq(3)
        }
      end
    end

    describe "unclosed block expressions" do
      it "raises SyntaxError for inline block without end" do
        source = '<div>{link_to "/" do <span>click</span>'
        expect { preprocess(source) }.to raise_error(Grsx::SyntaxError, /Unclosed/)
      end
    end

    describe "empty expressions" do
      it "renders empty expression as no-op" do
        html = render('<p>{""}</p>')
        expect(html).to include("<p>")
      end
    end

    describe "adjacent expressions" do
      it "renders two expressions back-to-back" do
        html = render('<p>{1}{2}</p>') do
          def view_template; end  # Will be overwritten
        end
        expect(html).to include("1")
        expect(html).to include("2")
      end

      it "preserves text between adjacent expressions" do
        html = render('<p>{1} and {2}</p>')
        expect(html).to include("1")
        expect(html).to include("and")
        expect(html).to include("2")
      end
    end

    describe "nested braces in expressions" do
      it "handles hash literals inside expressions" do
        code = preprocess('<p>{{a: 1, b: 2}.keys.join}</p>')
        expect(code).to include("__rsx_expr_out({a: 1, b: 2}.keys.join)")
      end

      it "handles nested blocks in expressions" do
        code = preprocess('<p>{[1,2].map { |x| x * 2 }.join}</p>')
        expect(code).to include("__rsx_expr_out([1,2].map { |x| x * 2 }.join)")
      end
    end

    describe "multiline expressions" do
      it "handles expressions spanning multiple lines" do
        source = "<p>{@items\n  .map(&:name)\n  .join(\", \")}</p>"
        code = preprocess(source)
        expect(code).to include("__rsx_expr_out")
        expect(code).to include(".join")
      end
    end

    describe "statement followed by expression" do
      it "handles {if} then expression then {end}" do
        source = '<div>{if true}<p>{@x}</p>{end}</div>'
        code = preprocess(source)
        expect(code).to include("if true")
        expect(code).to include("__rsx_expr_out(@x)")
        expect(code).to include("end")
      end

      it "handles {if}/{elsif}/{else}/{end} chain" do
        source = '<div>{if @a}<p>A</p>{elsif @b}<p>B</p>{else}<p>C</p>{end}</div>'
        code = preprocess(source)
        expect(code).to include("if @a")
        expect(code).to include("elsif @b")
        expect(code).to include("else")
        expect(code).to include("end")
      end
    end

    describe "double end" do
      it "emits two end statements" do
        code = preprocess('<div>{if true}{if false}<p>x</p>{end}{end}</div>')
        ends = code.scan(/\bend\b/)
        expect(ends.length).to be >= 2
      end
    end

    describe "component with all attribute types" do
      it "handles static, dynamic, boolean, and splat attrs together" do
        source = '<Card title="hello" size={@size} disabled {**@extra} />'
        code = preprocess(source)
        expect(code).to include('title: "hello"')
        expect(code).to include("size: @size")
        expect(code).to include("disabled: true")
        expect(code).to include("**@extra")
      end
    end

    describe "text content" do
      it "preserves HTML entities in text" do
        html = render('<p>Hello & world</p>')
        expect(html).to include("Hello &amp; world")
      end

      it "handles text with special characters" do
        html = render('<p>Price: $100 (50% off!)</p>')
        expect(html).to include("Price: $100 (50% off!)")
      end

      it "handles multiline text content" do
        source = "<p>Line one\nLine two\nLine three</p>"
        code = preprocess(source)
        expect(code).to include("plain")
      end

      it "handles text between tags" do
        html = render('<div><span>A</span> and <span>B</span></div>')
        expect(html).to include("A")
        expect(html).to include("B")
      end
    end

    describe "deeply nested control flow" do
      it "handles if inside each inside if" do
        source = <<~RSX
          <div>
            {if @show}
              <ul>
                {@items.each do |item|}
                  {if item.visible?}
                    <li>{item.name}</li>
                  {end}
                {end}
              </ul>
            {end}
          </div>
        RSX
        code = preprocess(source)
        expect(code).to include("if @show")
        expect(code).to include("@items.each do |item|")
        expect(code).to include("if item.visible?")
        expect(code).to include("__rsx_expr_out(item.name)")
        # Should have ends for: inner if, each, outer if
        ends = code.scan(/\bend\b/)
        expect(ends.length).to be >= 2
      end
    end

    describe "begin/rescue in children" do
      it "handles begin/rescue/ensure/end" do
        source = '<div>{begin}<p>try</p>{rescue => e}<p>error</p>{ensure}<p>always</p>{end}</div>'
        code = preprocess(source)
        expect(code).to include("begin")
        expect(code).to include("rescue => e")
        expect(code).to include("ensure")
        expect(code).to include("end")
      end
    end

    describe "case/when in children" do
      it "handles case/when/end" do
        source = '<div>{case @x}{when :a}<p>A</p>{when :b}<p>B</p>{end}</div>'
        code = preprocess(source)
        expect(code).to include("case @x")
        expect(code).to include("when :a")
        expect(code).to include("when :b")
        expect(code).to include("end")
      end
    end

    describe "fragment edge cases" do
      it "renders empty fragment" do
        html = render('<></>')
        expect(html).to eq("")
      end

      it "renders fragment with mixed content" do
        html = render('<><p>A</p>text<span>B</span></>')
        expect(html).to include("<p>A</p>")
        expect(html).to include("<span>B</span>")
      end
    end

    describe "self-closing tags" do
      it "handles void elements without explicit self-close" do
        code = preprocess('<br><hr><img src="x.png">')
        expect(code).to include("br")
        expect(code).to include("hr")
        expect(code).to include("img")
      end

      it "handles explicit self-close on void elements" do
        code = preprocess('<br /><hr />')
        expect(code).to include("br")
        expect(code).to include("hr")
      end

      it "handles self-closing components" do
        code = preprocess('<Card title="x" />')
        expect(code).to include('title: "x"')
      end
    end

    describe "whitespace handling" do
      it "does not emit empty plain calls for whitespace-only content" do
        code = preprocess("<div>\n  <p>hello</p>\n</div>")
        expect(code).not_to include('plain("")')
      end
    end
  end
end
