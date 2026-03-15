require "spec_helper"
require "tmpdir"

RSpec.describe Grsx::PhlexComponent do
  # Helper: define a PhlexComponent subclass with a given .rsx template string.
  # Writes a real .rsx file so the auto-discovery path exercises the filesystem.
  def define_component(rsx_source, &ruby_class_body)
    dir = Dir.mktmpdir("grsx_phlex_spec")
    rsx_path = File.join(dir, "my_component.rsx")
    rb_path  = File.join(dir, "my_component.rb")

    File.write(rsx_path, rsx_source)

    # Write the .rb file so source_location returns a known path
    File.write(rb_path, <<~RUBY)
      class MyPhlexTestComponent < Grsx::PhlexComponent
      end
    RUBY

    klass = Class.new(Grsx::PhlexComponent)

    # Manually trigger template loading with the known path
    klass.define_singleton_method(:rsx_template_path) { rsx_path }
    klass.send(:load_rsx_template)

    if ruby_class_body
      klass.class_eval(&ruby_class_body)
    end

    klass
  ensure
    FileUtils.remove_entry(dir) if dir && File.exist?(dir)
  end

  it "renders a simple HTML template" do
    klass = define_component("<div>hello</div>")
    html = klass.new.call
    expect(html).to include("<div>")
    expect(html).to include("hello")
    expect(html).to include("<div>")
  end

  # --- Fragment syntax <></> ---
  describe "fragment syntax <></>" do
    it "renders multiple siblings without a wrapper element" do
      klass = define_component(<<~RSX)
        <>
          <h1>Title</h1>
          <p>Body</p>
        </>
      RSX
      html = klass.new.call
      expect(html).to include("<h1>Title</h1>")
      expect(html).to include("<p>Body</p>")
      expect(html).not_to match(/<div|<span|<section/)
    end

    it "allows fragments inside a regular element" do
      klass = define_component('<div><><em>a</em><em>b</em></></div>')
      html = klass.new.call
      expect(html).to include("<div>")
      expect(html).to include("<em>a</em>")
      expect(html).to include("<em>b</em>")
      expect(html).not_to include("<></>") # no literal fragment tags in output
    end

    it "works with expressions inside fragments" do
      klass = define_component('<>{@greeting} {@name}</>') do
        def initialize(greeting:, name:); @greeting = greeting; @name = name; end
      end
      html = klass.new(greeting: "Hello", name: "World").call
      expect(html).to include("Hello")
      expect(html).to include("World")
    end
  end

  # --- Enumerable / Array output ---
  describe "Enumerable output in expressions" do
    it "renders each item from a map call" do
      klass = define_component('<ul>{@items.map { |i| "<li>#{i}</li>" }}</ul>') do
        def initialize(items:); @items = items; end
      end
      html = klass.new(items: %w[a b c]).call
      expect(html).to include("<ul>")
      expect(html).to include("a")
      expect(html).to include("b")
      expect(html).to include("c")
    end

    it "treats false as a silent no-op (conditional rendering pattern)" do
      klass = define_component('<p>{false}</p>')
      html = klass.new.call
      expect(html).to include("<p>")
      expect(html).not_to include("false")
    end

    it "treats nil as a silent no-op" do
      klass = define_component('<p>{nil}</p>')
      html = klass.new.call
      expect(html).to include("<p>")
      expect(html).not_to include("nil")
    end
  end

  # --- Compile error messages ---
  describe "TemplateCompileError" do
    it "raises TemplateCompileError with the .rsx filename for syntax errors" do
      file = Tempfile.new(["bad_component", ".rsx"])
      file.write("<div {broken")
      file.flush

      klass = Class.new(Grsx::PhlexComponent)
      expect {
        klass.send(:compile_template, file.path)
      }.to raise_error(Grsx::PhlexComponent::TemplateCompileError, /bad_component/)
    ensure
      file.close
      file.unlink
    end
  end

  # --- Conditional component rendering ---
  describe "conditional rendering with components" do
    it "renders a child component with && when condition is true" do
      inner_class = define_component("<em>shown</em>")
      stub_const("InnerComponent", inner_class)

      klass = define_component("<div>{@show && render(InnerComponent.new)}</div>") do
        def initialize(show:); @show = show; end
      end

      html = klass.new(show: true).call
      expect(html).to include("shown")
    end

    it "skips a child component with && when condition is false" do
      inner_class = define_component("<em>should-not-appear</em>")
      stub_const("HiddenComponent", inner_class)

      klass = define_component("<div>{@show && render(HiddenComponent.new)}</div>") do
        def initialize(show:); @show = show; end
      end

      html = klass.new(show: false).call
      expect(html).not_to include("should-not-appear")
    end
  end

  it "renders instance variables from initialize" do
    klass = define_component("<p>{@message}</p>") do
      def initialize(message:)
        @message = message
      end
    end
    html = klass.new(message: "World").call
    expect(html).to include("World")
    expect(html).to include("<p>")
  end

  it "auto-escapes user content in expressions" do
    klass = define_component("<p>{@value}</p>") do
      def initialize(value:)
        @value = value
      end
    end
    html = klass.new(value: '<script>alert("xss")</script>').call
    expect(html).not_to include("<script>")
    expect(html).to include("&lt;script&gt;")
  end

  it "renders nested HTML elements" do
    klass = define_component(<<~RSX)
      <section>
        <h1>{@title}</h1>
        <p>body text</p>
      </section>
    RSX
    klass.class_eval { def initialize(title:); @title = title; end }
    html = klass.new(title: "Hello!").call
    expect(html).to include("<section>")
    expect(html).to include("<h1>")
    expect(html).to include("Hello!")
    expect(html).to include("body text")
  end

  it "renders void elements" do
    klass = define_component("<br />")
    html = klass.new.call
    expect(html).to include("<br>")
  end

  it "renders attributes including dynamic ones" do
    klass = define_component('<a href={@url} class="link">{@label}</a>') do
      def initialize(url:, label:)
        @url = url
        @label = label
      end
    end
    html = klass.new(url: "/about", label: "About").call
    expect(html).to include('href="/about"')
    expect(html).to include('class="link"')
    expect(html).to include("About")
  end

  it "renders children via {content}" do
    # The wrapper component declares {content} which compiles to `yield`
    parent = define_component('<div class="wrapper">{content}</div>')

    # Phlex 2.x: block receives the component as the yielded-self argument
    child = Class.new(Phlex::HTML) { def view_template; p { plain("child content") }; end }
    html = parent.new.call { |wrapper| wrapper.render child.new }
    expect(html).to include('<div class="wrapper">')
    expect(html).to include("<p>child content</p>")
  end

  it "renders arithmetic expressions" do
    klass = define_component("<span>{1 + 1}</span>")
    html = klass.new.call
    expect(html).to include("2")
  end

  it "ignores nil expressions without output" do
    klass = define_component("<p>{nil}</p>")
    html = klass.new.call
    expect(html).to include("<p>")
    expect(html).to include("</p>")
    expect(html).not_to include("nil")
  end

  it "caches compiled templates across instances" do
    klass = define_component("<span>cached</span>")
    # Calling twice should use the same compiled method definition
    expect(klass.new.call).to include("cached")
    expect(klass.new.call).to include("cached")
  end

  describe "named slots" do
    it "defines with_X setter and has_X? predicate via slots DSL" do
      klass = define_component("<div>{slot(:header)}</div>") do
        slots :header
      end
      instance = klass.new
      expect(instance.has_header?).to be false
      instance.with_header { nil }
      expect(instance.has_header?).to be true
    end

    it "renders the slot content provided via with_X" do
      klass = define_component('<section><header>{slot(:title)}</header>{content}</section>') do
        slots :title
      end

      header_comp = Class.new(Phlex::HTML) { def view_template; h1 { plain("My Title") }; end }
      body_comp   = Class.new(Phlex::HTML) { def view_template; p  { plain("Body")     }; end }

      instance = klass.new
      instance.with_title { render header_comp.new }

      html = instance.call { |c| c.render body_comp.new }
      expect(html).to include("<h1>My Title</h1>")
      expect(html).to include("<p>Body</p>")
    end

    it "renders multiple independent named slots" do
      klass = define_component(
        '<div>{slot(:before)}<main>{content}</main>{slot(:after)}</div>'
      ) { slots :before, :after }

      before_comp = Class.new(Phlex::HTML) { def view_template; span { plain("PRE")  }; end }
      after_comp  = Class.new(Phlex::HTML) { def view_template; span { plain("POST") }; end }
      body_comp   = Class.new(Phlex::HTML) { def view_template; plain("BODY"); end }

      instance = klass.new
      instance.with_before { render before_comp.new }
      instance.with_after  { render after_comp.new }

      html = instance.call { |c| c.render body_comp.new }
      expect(html).to include("<span>PRE</span>")
      expect(html).to include("BODY")
      expect(html).to include("<span>POST</span>")
    end

    it "silently skips an unfilled slot" do
      klass = define_component('<div>{slot(:optional)}<p>body</p></div>') { slots :optional }
      html = klass.new.call
      expect(html).to include("<p>body</p>")
      expect(html).not_to include("nil")
    end

    it "supports slot chaining (fluent API)" do
      klass = define_component('<div>{slot(:a)}{slot(:b)}</div>') { slots :a, :b }
      a_comp = Class.new(Phlex::HTML) { def view_template; plain("A"); end }
      b_comp = Class.new(Phlex::HTML) { def view_template; plain("B"); end }

      # Chain .with_a.with_b
      instance = klass.new
        .with_a { render a_comp.new }
        .with_b { render b_comp.new }

      html = instance.call
      expect(html).to include("A")
      expect(html).to include("B")
    end
  end

  describe ".all_descendants" do
    it "includes defined subclasses" do
      klass = define_component("<span>x</span>")
      expect(Grsx::PhlexComponent.all_descendants).to include(klass)
    end
  end

  describe "template discovery" do
    it "exposes the template path" do
      dir = Dir.mktmpdir("grsx_phlex_disc")
      rsx_path = File.join(dir, "my_component.rsx")
      File.write(rsx_path, "<div>discovered</div>")

      klass = Class.new(Grsx::PhlexComponent)
      klass.define_singleton_method(:rsx_template_path) { rsx_path }
      klass.send(:load_rsx_template)

      html = klass.new.call
      expect(html).to include("discovered")
    ensure
      FileUtils.remove_entry(dir) if dir
    end
  end

  describe "#__rsx_expr_out" do
    subject(:runtime) { described_class.new }

    it "returns nil for nil" do
      expect(runtime.__rsx_expr_out(nil)).to be_nil
    end

    it "returns nil for empty string" do
      expect(runtime.__rsx_expr_out("")).to be_nil
    end

    it "renders Phlex components" do
      inner = Class.new(Phlex::HTML) { def view_template; span { plain("inner") }; end }
      html = runtime.call { runtime.__rsx_expr_out(inner.new) }
      expect(html).to include("<span>inner</span>")
    end
  end

  describe ".props DSL" do
    it "generates an initialize with required keyword args" do
      klass = define_component("<h1>{@title}</h1>") { props :title }
      html = klass.new(title: "Hello").call
      expect(html).to include("Hello")
    end

    it "generates an initialize with default keyword args" do
      klass = define_component("<span>{@size}</span>") { props size: :md }
      expect(klass.new.call).to include("md")
      expect(klass.new(size: :lg).call).to include("lg")
    end

    it "supports mixed required and default props" do
      klass = define_component("<p>{@label} {@variant}</p>") do
        props :label, variant: :primary
      end
      expect(klass.new(label: "OK").call).to include("OK")
      expect(klass.new(label: "OK").call).to include("primary")
      expect(klass.new(label: "OK", variant: :danger).call).to include("danger")
    end

    it "exposes _declared_props metadata" do
      klass = define_component("<div />") { props :title, size: :md }
      expect(klass._declared_props[:required]).to eq([:title])
      expect(klass._declared_props[:defaults]).to eq({ size: :md })
    end

    it "raises ArgumentError for missing required props" do
      klass = define_component("<div>{@name}</div>") { props :name }
      expect { klass.new }.to raise_error(ArgumentError, /name/)
    end
  end

  describe "streaming" do
    it "writes HTML to an IO-compatible buffer" do
      klass = define_component("<article><p>streamed</p></article>")
      buf = StringIO.new
      klass.new.call(buf)
      expect(buf.string).to include("<article>")
      expect(buf.string).to include("streamed")
    end

    it "matches string output from normal call" do
      klass = define_component("<div class=\"x\">{@val}</div>") do
        props :val
      end
      expected = klass.new(val: "hello").call
      buf = StringIO.new
      klass.new(val: "hello").call(buf)
      expect(buf.string).to eq(expected)
    end
  end

  describe ".component DSL" do
    it "creates an inline component that renders RSX" do
      klass = Grsx::PhlexComponent.component(:label) do
        <<~RSX
          <span>{@label}</span>
        RSX
      end

      html = klass.new(label: "Hello").call
      expect(html).to include("<span>")
      expect(html).to include("Hello")
    end

    it "supports default props" do
      klass = Grsx::PhlexComponent.component(:label, color: :blue) do
        <<~RSX
          <span class={@color}>{@label}</span>
        RSX
      end

      html = klass.new(label: "Tag").call
      expect(html).to include("blue")

      html = klass.new(label: "Tag", color: :red).call
      expect(html).to include("red")
    end

    it "creates a propless component when no args given" do
      klass = Grsx::PhlexComponent.component do
        <<~RSX
          <hr />
        RSX
      end

      html = klass.new.call
      expect(html).to include("<hr>")
    end

    it "works as a nested constant rendered by a parent component" do
      # Simulate the real usage pattern:
      #   class CardComponent < Grsx::PhlexComponent
      #     Badge = component(:label) { ... }
      #     template <<~RSX
      #       <div><Badge label="x" /></div>
      #     RSX
      #   end

      badge = Grsx::PhlexComponent.component(:label) do
        <<~RSX
          <em>{@label}</em>
        RSX
      end
      stub_const("BadgeComponent", badge)

      parent = define_component('<div><Badge label="new" /></div>')
      html = parent.new.call
      expect(html).to include("<div>")
      expect(html).to include("<em>")
      expect(html).to include("new")
    end

    it "supports slots on inline components" do
      klass = Grsx::PhlexComponent.component do
        <<~RSX
          <div>{slot(:header)}{content}</div>
        RSX
      end
      klass.slots :header

      header_comp = Class.new(Phlex::HTML) { def view_template; strong { plain("H") }; end }
      instance = klass.new
      instance.with_header { render header_comp.new }

      html = instance.call { |c| c.plain("body") }
      expect(html).to include("<strong>H</strong>")
      expect(html).to include("body")
    end
  end
end

