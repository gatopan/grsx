require "active_support/core_ext/string/strip"

RSpec.describe Grsx::Lexer do
  it "tokenizes text" do
    subject = Grsx::Lexer.new(Grsx::Template.new("Hello world"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [[:TEXT, "Hello world"]]
  end

  it "tokenizes html tags" do
    subject = Grsx::Lexer.new(Grsx::Template.new("<div></div>"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:CLOSE_TAG_DEF],
      [:OPEN_TAG_END],
      [:TAG_NAME, "div"],
      [:CLOSE_TAG_END]
    ]
  end

  it "tokenizes component tags" do
    redefine { ButtonComponent = Class.new }

    class Resolver
      def component?(name, template)
        name == "Button"
      end

      def component_class(name, template)
        name == "Button" ? ButtonComponent : nil
      end
    end

    subject = Grsx::Lexer.new(Grsx::Template.new("<Button></Button>"), Resolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "Button", type: :component, component_class: ButtonComponent }],
      [:CLOSE_TAG_DEF],
      [:OPEN_TAG_END],
      [:TAG_NAME, "Button"],
      [:CLOSE_TAG_END]
    ]
  end

  it "tokenizes self-closing html tags" do
    variants = ["<input />", "<input/>"]
    variants.each do |code|
      subject = Grsx::Lexer.new(Grsx::Template.new(code), Grsx::ComponentResolver.new)
      expect(subject.tokenize).to eq [
        [:OPEN_TAG_DEF],
        [:TAG_DETAILS, { name: "input", type: :html }],
        [:CLOSE_TAG_DEF],
        [:OPEN_TAG_END],
        [:CLOSE_TAG_END]
      ]
    end
  end

  it "tokenizes html5 doctype declaration" do
    subject = Grsx::Lexer.new(Grsx::Template.new("<!DOCTYPE html>"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:DECLARATION, "<!DOCTYPE html>"]
    ]
  end

  it "tokenizes older html4 doctype declaration" do
    template = <<-RBX.strip_heredoc.strip
      <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
    RBX

    subject = Grsx::Lexer.new(Grsx::Template.new(template), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [
        :DECLARATION,
        "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">"
      ]
    ]
  end

  it "tokenizes nested self-closing html tags" do
    subject = Grsx::Lexer.new(Grsx::Template.new("<div><br /></div>"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:CLOSE_TAG_DEF],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "br", type: :html }],
      [:CLOSE_TAG_DEF],
      [:OPEN_TAG_END],
      [:CLOSE_TAG_END],
      [:OPEN_TAG_END],
      [:TAG_NAME, "div"],
      [:CLOSE_TAG_END]
    ]
  end

  it "tokenizes self-closing html tags with attributes" do
    variants = ['<input thing="value" />', '<input thing="value"/>']
    variants.each do |code|
      subject = Grsx::Lexer.new(Grsx::Template.new(code), Grsx::ComponentResolver.new)
      expect(subject.tokenize).to eq [
        [:OPEN_TAG_DEF],
        [:TAG_DETAILS, { name: "input", type: :html }],
        [:OPEN_ATTRS],
        [:ATTR_NAME, "thing"],
        [:OPEN_ATTR_VALUE],
        [:TEXT, "value"],
        [:CLOSE_ATTR_VALUE],
        [:CLOSE_ATTRS],
        [:CLOSE_TAG_DEF],
        [:OPEN_TAG_END],
        [:CLOSE_TAG_END]
      ]
    end
  end

  it "tokenizes text inside a tag" do
    subject = Grsx::Lexer.new(Grsx::Template.new("<div>Hello world</div>"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Hello world"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "div"],
      [:CLOSE_TAG_END]
    ]
  end

  it "tokenizes an expression inside a tag" do
    subject = Grsx::Lexer.new(Grsx::Template.new("<div>{aVar}</div>"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:CLOSE_TAG_DEF],
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "aVar"],
      [:CLOSE_EXPRESSION],
      [:OPEN_TAG_END],
      [:TAG_NAME, "div"],
      [:CLOSE_TAG_END]
    ]
  end

  it "tokenizes two expressions next to one another" do
    subject = Grsx::Lexer.new(Grsx::Template.new("{aVar}{anotherVar}"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "aVar"],
      [:CLOSE_EXPRESSION],
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "anotherVar"],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "tokenizes an expression along with text inside a tag" do
    subject = Grsx::Lexer.new(Grsx::Template.new("<div>Hello {aVar}!</div>"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Hello "],
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "aVar"],
      [:CLOSE_EXPRESSION],
      [:TEXT, "!"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "div"],
      [:CLOSE_TAG_END]
    ]
  end

  it 'treats escaped \{ as text' do
    subject = Grsx::Lexer.new(Grsx::Template.new('Hey \{thing\}'), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:TEXT, 'Hey \{thing\}']
    ]
  end

  it "allows for { ... } to exist within an expression (e.g. a Ruby hash)" do
    subject = Grsx::Lexer.new(Grsx::Template.new('{thing = { hashKey: "value" }; moreCode}'), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, 'thing = { hashKey: "value" }; moreCode'],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "allows for expressions to have arbitrary brackets inside quoted strings" do
    subject = Grsx::Lexer.new(Grsx::Template.new('{something "quoted {bracket}" \'{}\' "\'{\'" more}'), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, 'something "quoted {bracket}" \'{}\' "\'{\'" more'],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "doesn't consider escaped quotes to end an expression quoted string" do
    subject = Grsx::Lexer.new(Grsx::Template.new('{"he said \"hello {there}\" loudly"}'), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, '"he said \"hello {there}\" loudly"'],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "tokenizes an expression that starts with a tag" do
    subject = Grsx::Lexer.new(Grsx::Template.new("{<h1>Title</h1>}"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, ""],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "h1", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Title"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "h1"],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, ""],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "tokenizes tags within a boolean expression" do
    subject = Grsx::Lexer.new(Grsx::Template.new("{true && <h1>Is true</h1>}"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "true && "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "h1", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Is true"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "h1"],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, ""],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "tokenizes self-closing tags within a boolean expression" do
    template_string = <<-RBX.strip_heredoc.strip
      {true && <br />}
    RBX

    subject = Grsx::Lexer.new(Grsx::Template.new(template_string), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "true && "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "br", type: :html }],
      [:CLOSE_TAG_DEF],
      [:OPEN_TAG_END],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, ""],
      [:CLOSE_EXPRESSION]
    ]
  end

  it "tokenizes nested tags within a boolean expression" do
    template_string = <<-RBX.strip_heredoc.strip
      {true && <h1><span>Hey</span></h1>}
    RBX

    subject = Grsx::Lexer.new(Grsx::Template.new(template_string), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "true && "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "h1", type: :html }],
      [:CLOSE_TAG_DEF],
        [:OPEN_TAG_DEF],
        [:TAG_DETAILS, { name: "span", type: :html }],
        [:CLOSE_TAG_DEF],
        [:TEXT, "Hey"],
        [:OPEN_TAG_END],
        [:TAG_NAME, "span"],
        [:CLOSE_TAG_END],
      [:OPEN_TAG_END],
      [:TAG_NAME, "h1"],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, ""],
      [:CLOSE_EXPRESSION]
    ]
  end

  it "does not specially tokenize boolean expressions that aren't followed by a tag" do
    subject = Grsx::Lexer.new(Grsx::Template.new("{true && 'hey'}"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "true && 'hey'"],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "allows for sub-expressions within a boolean expression tag" do
    subject = Grsx::Lexer.new(Grsx::Template.new("{true && <h1>Is {'hello'.upcase}</h1>}"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "true && "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "h1", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Is "],
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "'hello'.upcase"],
      [:CLOSE_EXPRESSION],
      [:OPEN_TAG_END],
      [:TAG_NAME, "h1"],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, ""],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "tokenizes tags within a ternary expression" do
    subject = Grsx::Lexer.new(Grsx::Template.new("{true ? <h1>Yes</h1> : <h2>No</h2>}"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "true ? "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "h1", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Yes"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "h1"],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, " : "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "h2", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "No"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "h2"],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, ""],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "tokenizes self-closing tags within a ternary expression" do
    subject = Grsx::Lexer.new(Grsx::Template.new("{true ? <br /> : <input />}"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "true ? "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "br", type: :html }],
      [:CLOSE_TAG_DEF],
      [:OPEN_TAG_END],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, " : "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "input", type: :html }],
      [:CLOSE_TAG_DEF],
      [:OPEN_TAG_END],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, ""],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "tokenizes tags within a boolean expression including an OR operator" do
    subject = Grsx::Lexer.new(Grsx::Template.new("{true || <p>Yes</p>}"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "true || "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "p", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Yes"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "p"],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, ""],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "tokenizes tags within a do..end block" do
    template = <<-RBX.strip
{3.times do
  <p>Hello</p>
end}
RBX
    subject = Grsx::Lexer.new(Grsx::Template.new(template), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "3.times do\n  "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "p", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Hello"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "p"],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, "\nend"],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "tokenizes tags within a do |var|..end block" do
    template = <<-RBX.strip
{3.times do |n|
  <p>Hello</p>
end}
RBX
    subject = Grsx::Lexer.new(Grsx::Template.new(template), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "3.times do |n|\n  "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "p", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Hello"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "p"],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, "\nend"],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "tokenizes tags within a {..} block" do
    subject = Grsx::Lexer.new(Grsx::Template.new("{3.times { <p>Hello</p> }}"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "3.times { "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "p", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Hello"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "p"],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, " }"],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "tokenizes tags within a {|var|..} block" do
    subject = Grsx::Lexer.new(Grsx::Template.new("{3.times { |n| <p>Hello</p> }}"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "3.times { |n| "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "p", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Hello"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "p"],
      [:CLOSE_TAG_END],
      [:EXPRESSION_BODY, " }"],
      [:CLOSE_EXPRESSION],
    ]
  end

  it "doesn't try to parse tags within %q(...) string notation" do
    template_string = <<-RBX.strip_heredoc.strip
      <div attr={%q(
        <p>something</p>
      )} />
    RBX
    subject = Grsx::Lexer.new(Grsx::Template.new(template_string), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "attr"],
      [:OPEN_ATTR_VALUE],
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "%q(\n  <p>something</p>\n)"],
      [:CLOSE_EXPRESSION],
      [:CLOSE_ATTR_VALUE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF],
      [:OPEN_TAG_END],
      [:CLOSE_TAG_END]
    ]
  end

  it "tokenizes value-less attributes" do
    subject = Grsx::Lexer.new(Grsx::Template.new("<button disabled>"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "button", type: :html }],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "disabled"],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF]
    ]
  end

  it "tokenizes attributes with double-quoted string values" do
    subject = Grsx::Lexer.new(Grsx::Template.new('<button type="submit">'), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "button", type: :html }],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "type"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "submit"],
      [:CLOSE_ATTR_VALUE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF]
    ]
  end

  it "treats escaped \\\" as part of the attribute value" do
    subject = Grsx::Lexer.new(Grsx::Template.new('<input value="Some \"value\"">'), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "input", type: :html }],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "value"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, 'Some \"value\"'],
      [:CLOSE_ATTR_VALUE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF]
    ]
  end

  it "tokenizes attributes with expression values" do
    subject = Grsx::Lexer.new(Grsx::Template.new("<input value={aVar}>"), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "input", type: :html }],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "value"],
      [:OPEN_ATTR_VALUE],
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "aVar"],
      [:CLOSE_EXPRESSION],
      [:CLOSE_ATTR_VALUE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF]
    ]
  end

  it "tokenizes a combination of types of attributes" do
    subject = Grsx::Lexer.new(Grsx::Template.new('<div foo bar="baz" thing={exprValue}>'), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "foo"],
      [:ATTR_NAME, "bar"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "baz"],
      [:CLOSE_ATTR_VALUE],
      [:ATTR_NAME, "thing"],
      [:OPEN_ATTR_VALUE],
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "exprValue"],
      [:CLOSE_EXPRESSION],
      [:CLOSE_ATTR_VALUE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF]
    ]
  end

  it "tokenizes a kwarg splat attribute" do
    subject = Grsx::Lexer.new(Grsx::Template.new('<div {**the_attrs}>'), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:OPEN_ATTRS],
      [:OPEN_ATTR_SPLAT],
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "the_attrs"],
      [:CLOSE_EXPRESSION],
      [:CLOSE_ATTR_SPLAT],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF]
    ]
  end

  it "adds a silent newline between tag name and attributes that come on the next line (for source mapping)" do
    code = <<-CODE.strip_heredoc.strip
      <div
        foo="bar">
      </div>
    CODE

    subject = Grsx::Lexer.new(Grsx::Template.new(code), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:NEWLINE],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "foo"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "bar"],
      [:CLOSE_ATTR_VALUE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF],
      [:TEXT, "\n"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "div"],
      [:CLOSE_TAG_END],
    ]
  end

  it "allows attributes to span multiple lines" do
    code = <<-CODE.strip_heredoc.strip
      <div foo="bar"
           baz="bip">
      </div>
    CODE

    subject = Grsx::Lexer.new(Grsx::Template.new(code), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "foo"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "bar"],
      [:CLOSE_ATTR_VALUE],
      [:NEWLINE],
      [:ATTR_NAME, "baz"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "bip"],
      [:CLOSE_ATTR_VALUE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF],
      [:TEXT, "\n"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "div"],
      [:CLOSE_TAG_END],
    ]
  end

  it "allows attributes to be on the next line after the tag name" do
    code = <<-CODE.strip_heredoc.strip
      <input
        foo="bar"
        baz="bip"
      />
    CODE

    subject = Grsx::Lexer.new(Grsx::Template.new(code), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "input", type: :html }],
      [:NEWLINE],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "foo"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "bar"],
      [:CLOSE_ATTR_VALUE],
      [:NEWLINE],
      [:ATTR_NAME, "baz"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "bip"],
      [:CLOSE_ATTR_VALUE],
      [:NEWLINE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF],
      [:OPEN_TAG_END],
      [:CLOSE_TAG_END],
    ]
  end

  it "tokenizes attributes with colon in the name" do
    code = <<-CODE.strip_heredoc.strip
      <svg version="1.1" xmlns:xlink="http://www.w3.org/1999/xlink" />
    CODE

    subject = Grsx::Lexer.new(Grsx::Template.new(code), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "svg", type: :html }],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "version"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "1.1"],
      [:CLOSE_ATTR_VALUE],
      [:ATTR_NAME, "xmlns:xlink"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "http://www.w3.org/1999/xlink"],
      [:CLOSE_ATTR_VALUE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF],
      [:OPEN_TAG_END],
      [:CLOSE_TAG_END],
    ]
  end

  it "tokenizes some big nested markup with attributes" do
    code = <<-CODE.strip_heredoc
      <div foo="bar">
        <h1>Some heading</h1>
        <p class="someClass">A paragraph</p>
        <div id={dynamicId} class="divClass">
          <p>More text</p>
        </div>
      </div>
    CODE

    subject = Grsx::Lexer.new(Grsx::Template.new(code), Grsx::ComponentResolver.new)
    expect(subject.tokenize).to eq [
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "foo"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "bar"],
      [:CLOSE_ATTR_VALUE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF],
      [:TEXT, "\n  "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "h1", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "Some heading"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "h1"],
      [:CLOSE_TAG_END],
      [:TEXT, "\n  "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "p", type: :html }],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "class"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "someClass"],
      [:CLOSE_ATTR_VALUE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF],
      [:TEXT, "A paragraph"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "p"],
      [:CLOSE_TAG_END],
      [:TEXT, "\n  "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "div", type: :html }],
      [:OPEN_ATTRS],
      [:ATTR_NAME, "id"],
      [:OPEN_ATTR_VALUE],
      [:OPEN_EXPRESSION],
      [:EXPRESSION_BODY, "dynamicId"],
      [:CLOSE_EXPRESSION],
      [:CLOSE_ATTR_VALUE],
      [:ATTR_NAME, "class"],
      [:OPEN_ATTR_VALUE],
      [:TEXT, "divClass"],
      [:CLOSE_ATTR_VALUE],
      [:CLOSE_ATTRS],
      [:CLOSE_TAG_DEF],
      [:TEXT, "\n    "],
      [:OPEN_TAG_DEF],
      [:TAG_DETAILS, { name: "p", type: :html }],
      [:CLOSE_TAG_DEF],
      [:TEXT, "More text"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "p"],
      [:CLOSE_TAG_END],
      [:TEXT, "\n  "],
      [:OPEN_TAG_END],
      [:TAG_NAME, "div"],
      [:CLOSE_TAG_END],
      [:TEXT, "\n"],
      [:OPEN_TAG_END],
      [:TAG_NAME, "div"],
      [:CLOSE_TAG_END],
      [:TEXT, "\n"]
    ]
  end

  context "comments" do
    it "tokenizes lines starting with # as NEWLINE" do
      template_string = <<-RBX.strip_heredoc.strip
        Hello
        # some comment
        world
      RBX

      subject = Grsx::Lexer.new(Grsx::Template.new(template_string), Grsx::ComponentResolver.new)
      expect(subject.tokenize).to eq [
        [:TEXT, "Hello\n"],
        [:NEWLINE],
        [:TEXT, "world"],
      ]
    end

    it "tokenizes the first line if starting with # as NEWLINE" do
      template_string = <<-RBX.strip_heredoc.strip
        # some comment
        Hello world
      RBX

      subject = Grsx::Lexer.new(Grsx::Template.new(template_string), Grsx::ComponentResolver.new)
      expect(subject.tokenize).to eq [
        [:NEWLINE],
        [:TEXT, "Hello world"],
      ]
    end

    it "tokenizes the last line if starting with # as NEWLINE" do
      template_string = <<-RBX.strip_heredoc.strip
      Hello world
      # some comment
      RBX

      subject = Grsx::Lexer.new(Grsx::Template.new(template_string), Grsx::ComponentResolver.new)
      expect(subject.tokenize).to eq [
        [:TEXT, "Hello world\n"],
        [:NEWLINE],
      ]
    end

    it "trims trailing whitespace from text before a comment line" do
      template_string = <<-RBX.strip_heredoc.strip
        Hello world
          # some indented comment
        Another text
      RBX

      subject = Grsx::Lexer.new(Grsx::Template.new(template_string), Grsx::ComponentResolver.new)
      expect(subject.tokenize).to eq [
        [:TEXT, "Hello world\n"],
        [:NEWLINE],
        [:TEXT, "Another text"]
      ]
    end

    it "allows comments as children of tags" do
      template_string = <<-RBX.strip_heredoc.strip
        <div>
          # some comment
        </div>
      RBX

      subject = Grsx::Lexer.new(Grsx::Template.new(template_string), Grsx::ComponentResolver.new)
      expect(subject.tokenize).to eq [
        [:OPEN_TAG_DEF],
        [:TAG_DETAILS, { name: "div", type: :html }],
        [:CLOSE_TAG_DEF],
        [:TEXT, "\n"],
        [:NEWLINE],
        [:OPEN_TAG_END],
        [:TAG_NAME, "div"],
        [:CLOSE_TAG_END],
      ]
    end

    it "treats an escaped \\# as TEXT" do
      subject = Grsx::Lexer.new(Grsx::Template.new('\# not a comment'), Grsx::ComponentResolver.new)
      expect(subject.tokenize).to eq [
        [:TEXT, '\# not a comment']
      ]
    end
  end

  # ---- Fragment tokenization ----

  describe "fragment syntax <></>" do
    it "emits OPEN_FRAGMENT for <>" do
      subject = Grsx::Lexer.new(Grsx::Template.new("<><p>x</p></>"), Grsx::ComponentResolver.new)
      types = subject.tokenize.map(&:first)
      expect(types).to include(:OPEN_FRAGMENT)
    end

    it "emits CLOSE_FRAGMENT for </>" do
      subject = Grsx::Lexer.new(Grsx::Template.new("<><p>x</p></>"), Grsx::ComponentResolver.new)
      types = subject.tokenize.map(&:first)
      expect(types).to include(:CLOSE_FRAGMENT)
    end

    it "emits one OPEN_FRAGMENT per <> and one CLOSE_FRAGMENT per </>" do
      subject = Grsx::Lexer.new(Grsx::Template.new("<><p>a</p><p>b</p></>"), Grsx::ComponentResolver.new)
      tokens = subject.tokenize.map(&:first)
      expect(tokens.count(:OPEN_FRAGMENT)).to eq(1)
      expect(tokens.count(:CLOSE_FRAGMENT)).to eq(1)
    end

    it "does not emit OPEN_TAG_DEF or TAG_DETAILS for the fragment angle brackets" do
      subject = Grsx::Lexer.new(Grsx::Template.new("<><span>hi</span></>"), Grsx::ComponentResolver.new)
      tokens = subject.tokenize
      # First OPEN_TAG_DEF should belong to <span>, not <>
      first_tag = tokens.find { |t| t.first == :TAG_DETAILS }
      expect(first_tag[1][:name]).to eq("span")
    end
  end

  # ---- SyntaxError line-number reporting ----

  describe "SyntaxError" do
    it "raises SyntaxError on invalid syntax" do
      subject = Grsx::Lexer.new(Grsx::Template.new("<div {broken>"), Grsx::ComponentResolver.new)
      expect { subject.tokenize }.to raise_error(Grsx::Lexer::SyntaxError)
    end

    it "reports line 1 for an error on the first line" do
      subject = Grsx::Lexer.new(Grsx::Template.new("<div @bad>"), Grsx::ComponentResolver.new)
      error = nil
      begin; subject.tokenize; rescue Grsx::Lexer::SyntaxError => e; error = e; end
      expect(error.line).to eq(1)
    end

    it "reports the correct line for a multi-line template error" do
      source = "<div>\n<p>good</p>\n<span @bad>"
      subject = Grsx::Lexer.new(Grsx::Template.new(source), Grsx::ComponentResolver.new)
      error = nil
      begin; subject.tokenize; rescue Grsx::Lexer::SyntaxError => e; error = e; end
      expect(error.line).to eq(3)
    end

    it "includes a 'near' snippet in the error message" do
      subject = Grsx::Lexer.new(Grsx::Template.new("<div {bad"), Grsx::ComponentResolver.new)
      error = nil
      begin; subject.tokenize; rescue Grsx::Lexer::SyntaxError => e; error = e; end
      expect(error.message).to match(/near/)
    end

    it "includes the filename when a template has an identifier" do
      template = Grsx::Template.new("<div @bad>", "/app/components/card_component.rbx")
      subject  = Grsx::Lexer.new(template, Grsx::ComponentResolver.new)
      error = nil
      begin; subject.tokenize; rescue Grsx::Lexer::SyntaxError => e; error = e; end
      expect(error.message).to include("card_component.rbx")
    end
  end
end
