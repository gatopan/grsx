# frozen_string_literal: true

require "spec_helper"
require "ostruct"

RSpec.describe Grsx::ComponentResolver do
  subject(:resolver) { described_class.new }

  # Simple stand-in for template identity (just needs #identifier)
  let(:template) { OpenStruct.new(identifier: "/app/views/home/index.rsx") }

  describe "#component?" do
    it "returns false for known HTML elements" do
      %w[div span p h1 section article form input button].each do |tag|
        expect(resolver.component?(tag, template)).to be false
      end
    end

    it "returns false for unknown tags that cannot be constantized" do
      expect(resolver.component?("NonExistentThing", template)).to be false
    end

    it "returns true when a matching Component class exists" do
      stub_const("CardComponent", Class.new)
      expect(resolver.component?("Card", template)).to be true
    end
  end

  describe "#component_class" do
    it "resolves simple names by appending Component" do
      klass = Class.new
      stub_const("CardComponent", klass)
      expect(resolver.component_class("Card", template)).to eq(klass)
    end

    it "resolves dotted names to namespaced constants" do
      klass = Class.new
      stub_const("Admin::ButtonComponent", klass)
      expect(resolver.component_class("Admin.Button", template)).to eq(klass)
    end

    it "returns nil when no matching constant exists" do
      expect(resolver.component_class("Nonexistent", template)).to be_nil
    end
  end

  describe "#component_namespaces" do
    it "defaults to an empty hash" do
      expect(resolver.component_namespaces).to eq({})
    end

    it "transforms keys to strings" do
      resolver.component_namespaces = { Pathname.new("/app/views/admin") => %w[Admin] }
      expect(resolver.component_namespaces.keys).to all(be_a(String))
    end

    it "resolves namespaced components when template path matches" do
      klass = Class.new
      stub_const("Admin::ButtonComponent", klass)

      resolver.component_namespaces = {
        "/app/views/admin" => %w[Admin]
      }

      admin_template = OpenStruct.new(identifier: "/app/views/admin/dashboard.rsx")
      expect(resolver.component_class("Button", admin_template)).to eq(klass)
    end

    it "does not resolve namespaced components when template path does not match" do
      stub_const("Admin::ButtonComponent", Class.new)

      resolver.component_namespaces = {
        "/app/views/admin" => %w[Admin]
      }

      public_template = OpenStruct.new(identifier: "/app/views/public/home.rsx")
      expect(resolver.component_class("Button", public_template)).to be_nil
    end
  end

  describe ".try_constantize" do
    it "returns the block result when constant exists" do
      stub_const("FooComponent", Class.new)
      result = described_class.try_constantize { ActiveSupport::Inflector.constantize("FooComponent") }
      expect(result).to eq(FooComponent)
    end

    it "returns nil for wrong constant names" do
      result = described_class.try_constantize { ActiveSupport::Inflector.constantize("lower_case") }
      expect(result).to be_nil
    end

    it "returns nil for uninitialized constants" do
      result = described_class.try_constantize { ActiveSupport::Inflector.constantize("DefinitelyNotDefined") }
      expect(result).to be_nil
    end
  end
end
