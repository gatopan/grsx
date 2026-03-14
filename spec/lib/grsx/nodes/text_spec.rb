RSpec.describe Grsx::Nodes::Text do
  describe "#precompile" do
    it "converts to raw" do
      result = Grsx::Nodes::Text.new("Some text").precompile
      expect(result.length).to eq 1
      expect(result.first).to be_a Grsx::Nodes::Raw
      expect(result.first.content).to eq "Some text"
    end
  end
end
