# GRSX

**RSX templates for Ruby, powered by [Phlex](https://phlex.fun).**

[![CI](https://github.com/gatopan/grsx/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/gatopan/grsx/actions?query=branch%3Amaster)

Write your Rails views and components using `.rsx` — Ruby with `<Tag>` syntax that compiles to Phlex DSL. Zero eval at render time.

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
- [The Grammar](#the-grammar)
- [Getting Started](#getting-started)
- [RSX Syntax](#rsx-syntax)
- [Views](#views)
- [Components](#components)
  - [Single-file Components](#single-file-components)
  - [Co-located Pair](#co-located-pair)
  - [Props](#props)
  - [Named Slots](#named-slots)
  - [Inline Components](#inline-components)
  - [Generator](#generator)
- [Component Resolution](#component-resolution)
  - [Auto-namespacing](#auto-namespacing)
- [Standalone Usage](#standalone-usage-without-rails)
- [Development](#development)

---

## How It Works

`.rsx` files are **Ruby-first** — standard Ruby with `<Tag>` as the only syntactic extension.

The preprocessor transforms `<Tag>` patterns into Phlex DSL calls:

```
.rsx source (Ruby + <Tag>) → Parser → AST → Codegen → Ruby code (Phlex DSL)
```

Compilation happens once at class-definition time. At render time Phlex executes the method directly — no parsing, no eval, no overhead.

In development, `.rsx` files are hot-reloaded automatically on each request.

---

## The Grammar

GRSX uses a **deterministic LL(1) recursive-descent parser**. Inside tag children, a single character of lookahead decides every production — no heuristics, no tokenizer, no guessing:

| First char | Production | Example |
|---|---|---|
| `<` | Tag or close tag | `<div>`, `</div>`, `<Card />` |
| `{` | Expression or statement | `{@name}`, `{if cond}`, `{end}` |
| anything else | Text content | `Hello world` |

**Rule: Ruby code in children must be wrapped in `{}`.**

This is what makes the grammar deterministic — the parser never needs to guess whether content is prose or Ruby. Bare text is text, always.

### Expressions vs Statements

Inside `{}`, the parser distinguishes two forms:

**Expressions** — interpolated into the output:
```jsx
<p>Hello {@user.name}</p>
<span>{Time.now.strftime("%H:%M")}</span>
```

**Statements** — control flow keywords emit as bare Ruby:
```jsx
<div>
  {if @logged_in}
    <nav>Dashboard</nav>
  {else}
    <a href="/login">Sign in</a>
  {end}
</div>
```

Keywords recognized as statements: `if`, `elsif`, `else`, `unless`, `case`, `when`, `begin`, `rescue`, `ensure`, `end`, `for`, `while`, `until`.

### Block Openers

For iterators and block methods, use the `{expr do |args|}...{end}` pattern:

```jsx
<ul>
  {@items.each do |item|}
    <li>{item.name}</li>
  {end}
</ul>
```

### Inline Blocks

For helpers that take a block with RSX content (like `link_to`), enclose the entire call in one `{}`:

```jsx
{link_to "/" do
  <span>Click me</span>
end}
```

---

## Getting Started

Add to your Gemfile:

```ruby
gem "grsx"
```

Requires **Ruby ≥ 3.1** and **Rails ≥ 7.1**.

Replace any ERB view with `.rsx`:

```jsx
// app/views/posts/index.html.rsx
<h1>Posts</h1>
<ul>
  {@posts.each do |post|}
    <li>{post.title}</li>
  {end}
</ul>
```

That's it. Same controller, same routes, same layout — just a better template syntax.

When you find yourself reusing markup, extract a component:

```ruby
// app/components/card_component.rsx
class CardComponent < Grsx::PhlexComponent
  props :title

  def view_template
    <article class="card">
      <h2>{@title}</h2>
      {content}
    </article>
  end
end
```

```jsx
// app/views/posts/index.html.rsx
<h1>Posts</h1>
{@posts.each do |post|}
  <Card title={post.title}>
    <p>{post.body}</p>
  </Card>
{end}
```

---

## RSX Syntax

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

Wrap control flow in `{}`:

```jsx
<div>
  {if logged_in?}
    <nav>Dashboard</nav>
  {else}
    <a href="/login">Sign in</a>
  {end}

  {case @role}
  {when :admin}
    <AdminPanel />
  {when :user}
    <UserPanel />
  {end}
</div>
```

### Loops

```jsx
<ul>
  {@items.each do |item|}
    <li>{item.name}</li>
  {end}
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

Both Ruby and HTML comments are stripped:

```jsx
# Ruby-style comment
<!-- HTML comment -->
<div>Visible</div>
```

### SVG

SVG elements are fully supported:

```jsx
<svg width="24" height="24" viewBox="0 0 24 24">
  <path d="M12 2L2 7" stroke="currentColor" />
  <circle cx="12" cy="12" r="10" fill="none" />
</svg>
```

---

## Views

GRSX registers `.rsx` as a first-class Rails template type — a drop-in replacement for ERB. Controller instance variables and helpers work automatically:

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
  {@posts.each do |post|}
    <li>{link_to post.title, post_path(post)}</li>
  {end}
</ul>
```

Partials, layouts, and all other view conventions work the same way — just use `.rsx` instead of `.erb`.

---

## Components

Components extend `Grsx::PhlexComponent` (which extends `Phlex::HTML`).

### Single-file Components

Define everything in one `.rsx` file — props, logic, and markup together:

```ruby
// app/components/card_component.rsx
class CardComponent < Grsx::PhlexComponent
  props :title, :body, size: :md

  def css_class
    "card card--#{@size}"
  end

  def view_template
    <article class={css_class}>
      <h2>{@title}</h2>
      <p>{@body}</p>
      {content}
    </article>
  end
end
```

GRSX auto-discovers single-file `.rsx` components — no separate `.rb` file needed.

### Co-located Pair

For complex components, split logic and markup into two files:

```
app/components/
  dashboard_component.rb    # Ruby logic, props, helpers
  dashboard_component.rsx   # Template only
```

```ruby
# dashboard_component.rb
class DashboardComponent < Grsx::PhlexComponent
  props :user
  slots :sidebar

  def stats
    @user.recent_activity.group_by(&:type)
  end
end
```

```jsx
// dashboard_component.rsx
<div class="dashboard">
  <aside>{slot(:sidebar)}</aside>
  <main>
    {@stats.each do |type, items|}
      <section>
        <h2>{type.titleize}</h2>
        <ul>
          {items.each do |item|}
            <li>{item.name}</li>
          {end}
        </ul>
      </section>
    {end}
  </main>
</div>
```

### Props

The `props` macro generates `initialize` with keyword arguments, instance variables, and `attr_reader` accessors:

```ruby
class CardComponent < Grsx::PhlexComponent
  props :title, :body, size: :md, disabled: false
end

# Equivalent to:
# def initialize(title:, body:, size: :md, disabled: false)
#   @title = title; @body = body; @size = size; @disabled = disabled
# end
```

> [!NOTE]
> Mutable defaults (`[]`, `{}`) are rejected at class-definition time with a helpful error message. Use `nil` and set the value in a manual `initialize` instead.

### Named Slots

Declare named content areas:

```ruby
class PageComponent < Grsx::PhlexComponent
  slots :sidebar, :footer
end
```

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

### Inline Components

Define sub-components directly inside a parent class:

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

### Generator

```bash
rails generate grsx:phlex_component Card title body --slots header footer
```

---

## Component Resolution

GRSX resolves component tags at runtime using `safe_constantize`:

| RSX Tag | Searches |
|---------|----------|
| `<Card />` | `CardComponent`, then `Card` |
| `<Admin.Button />` | `Admin::ButtonComponent`, then `Admin::Button` |
| `<UI.Forms.Input />` | `UI::Forms::InputComponent`, then `UI::Forms::Input` |

HTML elements (`div`, `span`, `p`, `svg`, etc.) are detected by name and rendered as plain tags — no class lookup.

Unknown lowercase tags raise a `SyntaxError` with a "did you mean?" suggestion:

```
Unknown element <dvi>. Did you mean <div>?
(components must start with uppercase, e.g. <Dvi>) (line 3)
  2 |   <p>ok</p>
> 3 |   <dvi>bad</dvi>
```

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

Now `<Button />` in any `.rsx` file under `app/views/admin/` resolves to `Admin::ButtonComponent` first, falling back to `ButtonComponent`.

---

## Standalone Usage (without Rails)

GRSX compiles `.rsx` source to Phlex DSL code. The compilation API works without Rails:

```ruby
code = Grsx.compile('<p class="greeting">{@message}</p>')
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
