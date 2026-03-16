# frozen_string_literal: true

require "spec_helper"

RSpec.describe Grsx::TemplateHandler do
  subject(:handler) { described_class.new }

  # Simulate the Rails Template object that ActionView passes to handlers
  let(:template) do
    double("ActionView::Template",
      source: template_source,
      identifier: "/app/views/posts/index.html.rsx",
      short_identifier: "posts/index.html.rsx",
      format: :html
    )
  end

  describe "#call" do
    context "with a simple template" do
      let(:template_source) { "<h1>Hello</h1>" }

      it "returns a string of Ruby code" do
        result = handler.call(template)
        expect(result).to be_a(String)
      end

      it "contains Grsx::PhlexRuntime reference" do
        result = handler.call(template)
        expect(result).to include("Grsx::PhlexRuntime")
      end

      it "contains render_in call for view context" do
        result = handler.call(template)
        expect(result).to include("render_in(self")
      end

      it "forwards local_assigns" do
        result = handler.call(template)
        expect(result).to include("local_assigns")
      end

      it "forwards controller assigns when available" do
        result = handler.call(template)
        expect(result).to include("assigns")
      end

      it "captures layout block as lambda for Phlex boundary crossing" do
        result = handler.call(template)
        expect(result).to include("lambda")
        expect(result).to include("yield")
        expect(result).to include("layout_block")
      end
    end

    context "with expressions" do
      let(:template_source) { "<p>{@title}</p>" }

      it "compiles the expression into the view_template body" do
        result = handler.call(template)
        expect(result).to include("@title")
        expect(result).to include("__rsx_expr_out")
      end
    end

    context "with component tags" do
      let(:template_source) { '<Card title="hello" />' }

      it "compiles component rendering" do
        stub_const("CardComponent", Class.new)
        result = handler.call(template, template_source)
        expect(result).to include('__resolve_rsx_const("Card")')
      end
    end

    context "with HTML attributes" do
      let(:template_source) { '<div class="container" id={@id}></div>' }

      it "compiles attributes into Phlex kwargs" do
        result = handler.call(template)
        expect(result).to include("class:")
        expect(result).to include("id:")
      end
    end

    context "with a nil source and template.source" do
      let(:template_source) { "<p>fallback</p>" }

      it "uses template.source when source argument is nil" do
        result = handler.call(template, nil)
        expect(result).to include("plain")
      end
    end

    context "with an explicit source argument" do
      let(:template_source) { "<p>ignored</p>" }

      it "uses the explicit source over template.source" do
        result = handler.call(template, "<h2>Override</h2>")
        expect(result).to include("h2")
        expect(result).not_to include("\"ignored\"")
      end
    end
  end

  describe "#supports_streaming?" do
    it "returns false (Phlex renders complete strings, no streaming)" do
      expect(handler.supports_streaming?).to be false
    end
  end

  describe "#handles_encoding?" do
    it "returns false (delegates to Rails)" do
      expect(handler.handles_encoding?).to be false
    end
  end

  describe "#translate_location" do
    let(:source) do
      "some code\nmore code # rsx:5\neven more\n"
    end

    let(:backtrace_location) do
      double("BacktraceLocation", lineno: 2)
    end

    it "maps compiled line to RSX source line via rsx:N marker" do
      spot = { first_lineno: 2, last_lineno: 2, first_column: 0, last_column: 10 }
      result = handler.translate_location(spot, backtrace_location, source)
      expect(result).not_to be_nil
      expect(result[:first_lineno]).to eq(5)
      expect(result[:last_lineno]).to eq(5)
    end

    it "returns nil when no rsx marker matches the line" do
      spot = { first_lineno: 1, last_lineno: 1, first_column: 0, last_column: 10 }
      loc = double("BacktraceLocation", lineno: 1)
      result = handler.translate_location(spot, loc, source)
      expect(result).to be_nil
    end

    it "returns nil for nil source" do
      spot = { first_lineno: 1, last_lineno: 1 }
      loc = double("BacktraceLocation", lineno: 1)
      expect(handler.translate_location(spot, loc, nil)).to be_nil
    end
  end

  describe "template annotations" do
    let(:template_source) { "<p>Hello</p>" }

    context "when annotations are enabled" do
      before do
        stub_const("ActionView::Base", Class.new {
          def self.annotate_rendered_view_with_filenames
            true
          end
        })
      end

      it "wraps output with BEGIN/END comments" do
        result = handler.call(template)
        expect(result).to include("BEGIN posts/index.html.rsx")
        expect(result).to include("END posts/index.html.rsx")
      end
    end

    context "when annotations are disabled" do
      before do
        stub_const("ActionView::Base", Class.new {
          def self.annotate_rendered_view_with_filenames
            false
          end
        })
      end

      it "does not include annotation comments" do
        result = handler.call(template)
        expect(result).not_to include("BEGIN")
        expect(result).not_to include("END")
      end
    end
  end

  describe ".call class method" do
    let(:template_source) { "<p>class method</p>" }

    it "instantiates and delegates to #call" do
      result = described_class.call(template)
      expect(result).to be_a(String)
      expect(result).to include("Grsx::PhlexRuntime")
    end
  end
end
