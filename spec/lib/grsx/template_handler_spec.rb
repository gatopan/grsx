# frozen_string_literal: true

require "spec_helper"

RSpec.describe Grsx::TemplateHandler do
  subject(:handler) { described_class.new }

  # Simulate the Rails Template object that ActionView passes to handlers
  let(:template) do
    double("ActionView::Template",
      source: template_source,
      identifier: "/app/views/posts/index.html.rsx"
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
        expect(result).to include("CardComponent")
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

    context "with invalid RSX" do
      let(:template_source) { "<div><span></div>" }

      it "raises a parse error at handler call time" do
        expect { handler.call(template) }.to raise_error(Grsx::Parser::ParseError)
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
end
