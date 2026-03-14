require "spec_helper"

RSpec.describe Grsx::PropInspector do
  describe ".scan_code" do
    it "finds single ivar" do
      code = 'div { plain(@title) }'
      expect(described_class.scan_code(code)).to eq([:title])
    end

    it "finds multiple ivars sorted and deduped" do
      code = 'div { plain(@body); plain(@title); plain(@title) }'
      expect(described_class.scan_code(code)).to eq([:body, :title])
    end

    it "returns empty array when no ivars" do
      expect(described_class.scan_code('div { plain("hello") }')).to eq([])
    end

    it "matches underscore-containing ivar names" do
      code = 'plain(@user_name); plain(@item_count)'
      expect(described_class.scan_code(code)).to eq([:item_count, :user_name])
    end

    it "handles internal Phlex state ivars gracefully" do
      # @_state and @_slots are internal — PropInspector scans them all;
      # the props DSL filters by declared names
      code = 'div { @_state.buffer << "x"; plain(@title) }'
      result = described_class.scan_code(code)
      expect(result).to include(:title)
    end
  end

  describe ".scan_tree" do
    def parse(source)
      template = Grsx::Template.new(source, "test.rsx")
      tokens = Grsx::Lexer.new(template, Grsx.configuration.element_resolver).tokenize
      Grsx::Parser.new(tokens).parse
    end

    it "finds ivar in expression group" do
      root = parse("<p>{@title}</p>")
      expect(described_class.scan_tree(root)).to eq([:title])
    end

    it "finds ivars in nested elements" do
      root = parse("<div><h1>{@title}</h1><p>{@body}</p></div>")
      expect(described_class.scan_tree(root)).to eq([:body, :title])
    end

    it "finds ivar in attribute expressions" do
      root = parse('<a href={@url}>link</a>')
      expect(described_class.scan_tree(root)).to include(:url)
    end

    it "returns empty for static templates" do
      root = parse("<div>hello world</div>")
      expect(described_class.scan_tree(root)).to eq([])
    end

    it "finds ivars in multiple expression groups" do
      root = parse("<div>{@a}{@b}{@a}</div>")
      expect(described_class.scan_tree(root)).to eq([:a, :b])
    end
  end
end
