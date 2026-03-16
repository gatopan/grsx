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
      code = 'div { @_state.buffer << "x"; plain(@title) }'
      result = described_class.scan_code(code)
      expect(result).to include(:title)
    end
  end
end
