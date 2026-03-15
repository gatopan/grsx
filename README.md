# GRSX

**JSX-flavored templates for Ruby, powered by [Phlex](https://phlex.fun).**

[![CI](https://github.com/gatopan/grsx/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/gatopan/grsx/actions?query=branch%3Amaster)

Write server-rendered components using `.rsx` templates that compile directly to Phlex DSL at class-definition time — zero eval at render time.

```jsx
<body>
  <Hero size="fullscreen" {**@extra_attrs}>
    <h1>Hello {@name}</h1>
    <Button to={about_path}>Learn more</Button>
  </Hero>
</body>
```

## Table of Contents

- [How It Works](#how-it-works)
- [Getting Started](#getting-started)
- [Template Syntax](#template-syntax)
- [Components](#components)
  - [Props](#props)
  - [Named Slots](#named-slots)
  - [Inline Templates](#inline-templates)
  - [Template-less Components](#template-less-components)
  - [Generator](#generator)
- [RSX Views](#rsx-views)
- [Component Resolution](#component-resolution)
  - [Auto-namespacing](#auto-namespacing)
- [Standalone Usage (without Rails)](#standalone-usage-without-rails)
- [Development](#development)

---

## How It Works

GRSX has a three-stage compilation pipeline:

```
.rsx template → Lexer → Parser → PhlexCompiler → Ruby code (Phlex DSL)
```

The compiled code is `class_eval`'d into `view_template` at class-definition time, not at render time. At render time, Phlex executes the method directly — no parsing, no eval, no overhead.

```ruby
# card_component.rsx
# <article class="card"><h2>{@title}</h2>{content}</article>

# compiles to:
def view_template
  article(class: "card") do
    h2 do
      __rsx_expr_out(@title)
    end
    yield
  end
end
```

In development, the `PhlexReloader` middleware watches `.rsx` files for changes and recompiles automatically on each request.

---

## Getting Started

Add to your Gemfile:

```ruby
gem "grsx"
```

Requires **Ruby ≥ 3.1** and **Rails ≥ 7.1**.

Create a component:

```ruby
# app/components/greeting_component.rb
class GreetingComponent < Grsx::PhlexComponent
  def initialize(name:)
    @name = name
  end
end
```

```jsx
// app/components/greeting_component.rsx
<div>
  <h1>Hello {@name}</h1>
  {content}
</div>
```

Render from a controller:

```ruby
class WelcomeController < ApplicationController
  def index
    render GreetingComponent.new(name: "World")
  end
end
```

Or from another `.rsx` template:

```jsx
<Greeting name="World">
  <p>Welcome to GRSX.</p>
</Greeting>
```

---

## Template Syntax

### Expressions

Use braces `{}` to embed Ruby expressions:

```jsx
<p class={@dynamic_class}>Hello {"world".upcase}</p>
```

### Attribute Spreading

Splat a hash into attributes:

```jsx
<div {**{class: "card"}} {**@more_attrs}></div>
```

### Conditionals

```jsx
<div>
  {logged_in? && <nav>Dashboard</nav>}
  {admin? ? <AdminPanel /> : <UserPanel />}
</div>
```

### Loops

```jsx
<ul>
  {@items.map { |item| <li>{item.name}</li> }}
</ul>
```

### Blocks

```jsx
{link_to "/" do
  <span>Click me</span>
end}
```

### Fragments

Render multiple elements without a wrapper:

```jsx
<>
  <h1>Title</h1>
  <p>Body</p>
</>
```

### Comments

Lines starting with `#` are stripped from the output:

```jsx
# This won't appear in the HTML
<div>Visible</div>
```

### Declarations

Pass-through for `<!DOCTYPE>` and similar:

```jsx
<!DOCTYPE html>
<html>
  <body>{content}</body>
</html>
```

---

## Components

All components inherit from `Grsx::PhlexComponent` (which extends `Phlex::HTML`).

Place the `.rb` file and `.rsx` template side by side with matching names — GRSX automatically discovers and compiles the template.

```
app/components/
  card_component.rb
  card_component.rsx
```

### Props

For simple prop-to-ivar mapping, use the `props` macro:

```ruby
class CardComponent < Grsx::PhlexComponent
  props :title, :body, size: :md, disabled: false
end
```

This generates an `initialize` with keyword arguments, instance variables, and `attr_reader` accessors:

```ruby
# Equivalent to writing:
# def initialize(title:, body:, size: :md, disabled: false)
#   @title = title; @body = body; @size = size; @disabled = disabled
# end
```

> [!NOTE]
> Mutable defaults (`[]`, `{}`) are rejected at class-definition time with a helpful error message. Use `nil` and set the value in a manual `initialize` instead.

For complex initialization logic, override `initialize` directly instead of using `props`.

### Named Slots

Declare named content areas:

```ruby
class PageComponent < Grsx::PhlexComponent
  slots :sidebar, :footer
end
```

Use in the template:

```jsx
// page_component.rsx
<div class="layout">
  <aside>{slot(:sidebar)}</aside>
  <main>{content}</main>
  <footer>{slot(:footer)}</footer>
</div>
```

Fill slots from the caller:

```ruby
page = PageComponent.new
page.with_sidebar { render NavComponent.new }
page.with_footer { plain("© 2026") }
render page
```

Each slot also has a predicate: `page.has_sidebar?`.

### Inline Templates

For simple components, skip the `.rsx` file and embed the template directly:

```ruby
class BadgeComponent < Grsx::PhlexComponent
  props :label, color: :blue

  template <<~RSX
    <span class={@color}>{@label}</span>
  RSX
end
```

The RSX compiles at class-definition time — same performance as a co-located file. Use whichever style fits the component's complexity.

### Inline Components

Define sub-components directly inside a parent class — no separate file, no global namespace pollution:

```ruby
class CardComponent < Grsx::PhlexComponent
  Badge = component(:label, color: :blue) do
    <<~RSX
      <span class={@color}>{@label}</span>
    RSX
  end

  props :title

  template <<~RSX
    <article class="card">
      <h2>{@title}</h2>
      <Badge label="New" />
      {content}
    </article>
  RSX
end
```

`component` accepts the same prop signature as `props` (required symbols + keyword defaults) and returns a `PhlexComponent` subclass. Assign it to a constant and reference it as a tag in your RSX. Slots work too — call `.slots` on the returned class.

### Template-less Components

Override `view_template` directly for Ruby-only components:

```ruby
class BadgeComponent < Grsx::PhlexComponent
  props :label

  def view_template
    span(class: "badge") { plain(@label) }
  end
end
```

### Generator

```bash
rails generate grsx:phlex_component Card title body --slots header footer
```

Produces:

```
app/components/card_component.rb
app/components/card_component.rsx
```

---

## RSX Views

GRSX registers `.rsx` as a first-class Rails view template type — like ERB, Haml, or Slim. Controller instance variables and helpers work automatically:

```ruby
# app/controllers/posts_controller.rb
class PostsController < ApplicationController
  def index
    @posts = Post.all
  end
end
```

```jsx
// app/views/posts/index.html.rsx
<h1>Posts</h1>
<ul>
  {@posts.map { |post| <li>{post.title}</li> }}
</ul>
```

Partials work too:

```jsx
// app/views/posts/_post.rsx
<article>
  <h2>{@post.title}</h2>
  <p>{@post.body}</p>
</article>
```

---

## Component Resolution

GRSX resolves component tags by appending `Component` to the tag name:

| RSX Tag | Ruby Class |
|---------|-----------|
| `<Card />` | `CardComponent` |
| `<Admin.Button />` | `Admin::ButtonComponent` |
| `<UI.Forms.Input />` | `UI::Forms::InputComponent` |

HTML elements are detected by name and rendered as plain tags — no class lookup.

### Auto-namespacing

Avoid typing the namespace prefix on every component tag:

```ruby
# config/initializers/grsx.rb
Grsx.configure do |config|
  config.element_resolver.component_namespaces = {
    Rails.root.join("app", "views", "admin") => %w[Admin],
    Rails.root.join("app", "components", "admin") => %w[Admin],
  }
end
```

Now `<Button />` in any `.rsx` file under `app/views/admin/` will resolve to `Admin::ButtonComponent` first, falling back to `ButtonComponent`.

### Custom Resolver

Replace the default resolver entirely:

```ruby
Grsx.configure do |config|
  config.element_resolver = MyResolver.new
end
```

Where `MyResolver` implements:

- `component?(name, template) → Boolean`
- `component_class(name, template) → Class`

---

## Standalone Usage (without Rails)

GRSX compiles `.rsx` templates to Phlex DSL code. The compilation API works without Rails:

```ruby
template = Grsx::Template.new('<p class="greeting">{@message}</p>')
code = Grsx.compile(template)
# => "p(class: \"greeting\") do\n__rsx_expr_out(@message)\nend"
```

For rendering without Rails, use `PhlexRuntime`:

```ruby
class MyView < Grsx::PhlexRuntime
  def initialize(message:)
    @message = message
  end
end
```

---

## Development

```bash
bundle install
bundle exec rspec            # run test suite
bundle exec appraisal rspec  # run against all supported Rails versions
```

After updating dependency versions in the gemspec:

```bash
bundle exec appraisal install
```

Supported: **Rails 7.1 · 7.2 · 8.0 · 8.1**

## License

MIT — see [LICENSE.txt](LICENSE.txt).
