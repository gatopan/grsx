require "spec_helper"
require "tmpdir"

RSpec.describe Rbexy::PhlexComponent do
  # Helper: define a PhlexComponent subclass with a given .rbx template string.
  # Writes a real .rbx file so the auto-discovery path exercises the filesystem.
  def define_component(rbx_source, &ruby_class_body)
    dir = Dir.mktmpdir("rbexy_phlex_spec")
    rbx_path = File.join(dir, "my_component.rbx")
    rb_path  = File.join(dir, "my_component.rb")

    File.write(rbx_path, rbx_source)

    # Write the .rb file so source_location returns a known path
    File.write(rb_path, <<~RUBY)
      class MyPhlexTestComponent < Rbexy::PhlexComponent
      end
    RUBY

    klass = Class.new(Rbexy::PhlexComponent)

    # Manually trigger template loading with the known path
    klass.define_singleton_method(:rbx_template_path) { rbx_path }
    klass.send(:load_rbx_template)

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
    expect(html).to include("</div>")
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
    klass = define_component(<<~RBX)
      <section>
        <h1>{@title}</h1>
        <p>body text</p>
      </section>
    RBX
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
      expect(Rbexy::PhlexComponent.all_descendants).to include(klass)
    end
  end

  describe "template discovery" do
    it "exposes the template path" do
      dir = Dir.mktmpdir("rbexy_phlex_disc")
      rbx_path = File.join(dir, "my_component.rbx")
      File.write(rbx_path, "<div>discovered</div>")

      klass = Class.new(Rbexy::PhlexComponent)
      klass.define_singleton_method(:rbx_template_path) { rbx_path }
      klass.send(:load_rbx_template)

      html = klass.new.call
      expect(html).to include("discovered")
    ensure
      FileUtils.remove_entry(dir) if dir
    end
  end

  describe "#__rbx_expr_out" do
    subject(:runtime) { described_class.new }

    it "returns nil for nil" do
      expect(runtime.__rbx_expr_out(nil)).to be_nil
    end

    it "returns nil for empty string" do
      expect(runtime.__rbx_expr_out("")).to be_nil
    end

    it "renders Phlex components" do
      inner = Class.new(Phlex::HTML) { def view_template; span { plain("inner") }; end }
      html = runtime.call { runtime.__rbx_expr_out(inner.new) }
      expect(html).to include("<span>inner</span>")
    end
  end
end
