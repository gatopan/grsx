require "spec_helper"

RSpec.describe Rbexy::PhlexCompiler do
  def phlex_compile(source)
    template = Rbexy::Template.new(source)
    Rbexy.phlex_compile(template)
  end

  def render_phlex(source)
    code = phlex_compile(source)
    runtime = Rbexy::PhlexRuntime.new
    # PhlexRuntime#call takes an optional block; we evaluate our compiled code inside view_template
    runtime.call { runtime.instance_eval(code) }
  end

  describe "HTML elements" do
    it "renders a simple element" do
      html = render_phlex("<div>hello</div>")
      expect(html).to include("<div>")
      expect(html).to include("hello")
      expect(html).to include("</div>")
    end

    it "renders nested elements" do
      html = render_phlex("<section><p>inner</p></section>")
      expect(html).to match(/<section>.*<p>.*inner.*<\/p>.*<\/section>/m)
    end

    it "renders attributes" do
      html = render_phlex('<div class="outer" id="main">hi</div>')
      expect(html).to include('class="outer"')
      expect(html).to include('id="main"')
    end

    it "renders an empty element" do
      html = render_phlex("<span></span>")
      expect(html).to include("<span>")
      expect(html).to include("</span>")
    end

    it "renders void elements" do
      html = render_phlex("<br />")
      expect(html).to include("<br>")
    end

    it "renders img void element with attributes" do
      html = render_phlex('<img src="/pic.jpg" alt="photo" />')
      expect(html).to include("img")
      expect(html).to include("src")
      expect(html).to include("alt")
    end

    it "renders bare boolean attributes as true (disabled, required, checked)" do
      code = phlex_compile('<input type="checkbox" disabled />')
      expect(code).to include("disabled: true")
      expect(code).to include('type: "checkbox"')
    end

    it "renders boolean component props as true" do
      stub_const("ButtonComponent", Class.new)
      code = phlex_compile("<Button primary />")
      expect(code).to include("primary: true")
    end
  end

  describe "text content" do
    it "escapes HTML in text nodes" do
      html = render_phlex("<div>hello &amp; world</div>")
      expect(html).to include("hello")
    end

    it "escapes HTML in expressions" do
      html = render_phlex('<div>{"<script>alert(1)</script>"}</div>')
      expect(html).not_to include("<script>")
      expect(html).to include("&lt;script&gt;")
    end
  end

  describe "expressions" do
    it "renders string expressions" do
      html = render_phlex('<span>{"hello"}</span>')
      expect(html).to include("hello")
    end

    it "renders numeric expressions" do
      html = render_phlex('<p>{42}</p>')
      expect(html).to include("42")
    end

    it "supports multi-token expressions" do
      html = render_phlex('<p>{1 + 1}</p>')
      expect(html).to include("2")
    end

    it "does not output nil expressions" do
      html = render_phlex('<p>{nil}</p>')
      expect(html).to include("<p>")
      expect(html).to include("</p>")
    end
  end

  describe "generated code" do
    it "emits a div block for an element with children" do
      code = phlex_compile("<div>hello</div>")
      expect(code).to include("div do")
      expect(code).to include("plain(\"hello\")")
      expect(code).to include("end")
    end

    it "emits a void element call with no block" do
      code = phlex_compile("<br />")
      expect(code).to include("br")
      expect(code).not_to include("do")
    end

    it "emits render() for resolved component elements" do
      # ComponentResolver tries constantize("TestButtonComponent") automatically
      stub_const("TestButtonComponent", Class.new)

      code = phlex_compile("<TestButton label=\"ok\" />")
      expect(code).to include("render(::TestButtonComponent.new(")
      expect(code).to include("label:")
    end

    it "emits __rbx_expr_out for expressions" do
      code = phlex_compile("<div>{@title}</div>")
      expect(code).to include("__rbx_expr_out(@title)")
    end
  end

  describe "attribute name normalization" do
    it "passes through simple lowercase attributes unchanged" do
      code = phlex_compile('<div class="active">hi</div>')
      expect(code).to include("class: \"active\"")
    end

    it "passes through 'for' on label unchanged" do
      code = phlex_compile('<label for="email">Email</label>')
      expect(code).to include("for: \"email\"")
    end

    it "converts kebab-case to underscore (the only transformation needed)" do
      code = phlex_compile('<input tab-index="1" />')
      expect(code).to include("tab_index: \"1\"")
    end

    it "converts data-* kebab attributes to underscored kwargs (Phlex re-hyphenates in output)" do
      code = phlex_compile('<div data-controller="dropdown">x</div>')
      expect(code).to include("data_controller: \"dropdown\"")
    end

    it "converts aria-* kebab attributes to underscored kwargs" do
      code = phlex_compile('<button aria-label="Close">x</button>')
      expect(code).to include("aria_label: \"Close\"")
    end
  end

  describe "key prop stripping" do
    it "silently drops the key prop from component calls" do
      stub_const("ItemComponent", Class.new)
      code = phlex_compile('<Item key={i} title="x" />')
      expect(code).to include("title:")
      expect(code).not_to include("key:")
    end
  end

  describe "conditional rendering patterns" do
    it "generates code that works with && when truthy" do
      html = render_phlex('<div>{1 > 0 && "yes"}</div>')
      expect(html).to include("yes")
    end

    it "is safe for falsy && (false short-circuit)" do
      html = render_phlex('<div>{false && "nope"}</div>')
      expect(html).not_to include("nope")
    end
  end
end
