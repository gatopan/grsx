# GRSX — JSX-flavored templates for Ruby, powered by Phlex

[![Build Status](https://github.com/gatopan/grsx/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/gatopan/grsx/actions?query=branch%3Amaster)

Write server-rendered components using JSX-style `.rsx` templates that compile to [Phlex](https://phlex.fun) DSL — no eval at render time.

* [Getting Started](#getting-started-with-rails)
* [Template Syntax](#template-syntax)
* [Components](#components)
  * [Props DSL](#props-dsl)
  * [Named Slots](#named-slots)
  * [Template-less components](#template-less-components)
* [Advanced](#advanced)
  * [Component resolution](#component-resolution)
  * [Usage outside of Rails](#usage-outside-of-rails)

## Example

Use custom Phlex components from `.rsx` templates just like React components in JSX:

```jsx
<body>
  <Hero size="fullscreen" {**splat_some_attributes}>
    <h1>Hello {@name}</h1>
    <p>Welcome to GRSX.</p>
    <Button to={about_path}>Learn more</Button>
  </Hero>
</body>
```

Components are plain Ruby classes backed by co-located `.rsx` templates:

```ruby
class HeroComponent < Grsx::PhlexComponent
  props :size
end
```

```jsx
# hero_component.rsx
<section class={@size}>
  {content}
</section>
```

## Getting Started (with Rails)

Add it to your Gemfile and `bundle install`:

```ruby
gem "grsx"
```

Requires **Rails 7.1+** and **Ruby 3.1+**.

Create your first component at `app/components/hello_world_component.rb`:

```ruby
class HelloWorldComponent < Grsx::PhlexComponent
  props :name
end
```

With a template `app/components/hello_world_component.rsx`:

```jsx
<div>
  <h1>Hello {@name}</h1>
  {content}
</div>
```

Render it from a controller:

```ruby
class HelloWorldsController < ApplicationController
  def index
    render HelloWorldComponent.new(name: "World")
  end
end
```

## Template Syntax

Ruby expressions go in braces:

```jsx
<p class={@dynamic_class}>
  Hello {"world".upcase}
</p>
```

Splat a hash into attributes:

```jsx
<div {**{class: "myClass"}} {**@more_attrs}></div>
```

Conditional rendering:

```jsx
<div>
  {some_boolean && <h1>Welcome</h1>}
  {another_boolean ? <p>Option One</p> : <p>Option Two</p>}
</div>
```

Loops:

```jsx
<ul>
  {[1, 2, 3].map { |n| <li>{n}</li> }}
</ul>
```

Blocks:

```jsx
{link_to "/" do
  <span>Click me</span>
end}
```

JSX fragments (no wrapper element):

```jsx
<>
  <h1>Title</h1>
  <p>Body</p>
</>
```

Comments (lines starting with `#`):

```jsx
# This won't appear in the HTML
<div>visible</div>
```

## Components

### `Grsx::PhlexComponent`

All GRSX components inherit from `Grsx::PhlexComponent` (which extends `Phlex::HTML`). Define a `.rb` file and a co-located `.rsx` template with matching names:

```ruby
# app/components/card_component.rb
class CardComponent < Grsx::PhlexComponent
  def initialize(title:)
    @title = title
  end
end
```

```jsx
# app/components/card_component.rsx
<article class="card">
  <h2>{@title}</h2>
  {content}
</article>
```

The `.rsx` template compiles to a `view_template` method at class definition time — not at render time.

### Props DSL

For simple prop-to-ivar mapping, use the `props` macro instead of writing `initialize` by hand:

```ruby
class CardComponent < Grsx::PhlexComponent
  props :title, :body, size: :md, disabled: false
end
```

This generates `initialize(title:, body:, size: :md, disabled: false)` with corresponding `@title`, `@body`, `@size`, `@disabled` instance variables and `attr_reader` accessors.

### Named Slots

Declare named content slots for complex layouts:

```ruby
class CardComponent < Grsx::PhlexComponent
  slots :header, :footer
end
```

```jsx
# card_component.rsx
<article>
  <header>{slot(:header)}</header>
  <main>{content}</main>
  <footer>{slot(:footer)}</footer>
</article>
```

Fill slots from the caller:

```ruby
card = CardComponent.new
card.with_header { render LogoComponent.new }
card.with_footer { plain("© 2026") }
render card
```

### Template-less components

Override `view_template` directly for components that don't need `.rsx`:

```ruby
class BadgeComponent < Grsx::PhlexComponent
  props :label

  def view_template
    span(class: "badge") { plain(@label) }
  end
end
```

### Generator

Generate a component scaffold:

```
rails generate grsx:phlex_component Card title body --slots header footer
```

## Advanced

### Component resolution

By default, GRSX resolves component tags to Ruby classes named `#{tag}Component`:

* `<PageHeader />` → `PageHeaderComponent`
* `<Admin.Button />` → `Admin::ButtonComponent`

Customize with a resolver:

```ruby
# config/initializers/grsx.rb
Grsx.configure do |config|
  config.element_resolver = MyResolver.new
end
```

Where `MyResolver` implements:

* `component?(name, template) → Boolean`
* `component_class(name, template) → Class`

### Usage outside of Rails

GRSX compiles `.rsx` to Phlex DSL Ruby code:

```ruby
template = Grsx::Template.new("<p>{@greeting}</p>")
code = Grsx.compile(template)
# => "__rsx_expr_out(@greeting)"
```

Use `Grsx::PhlexRuntime` for standalone rendering without Rails:

```ruby
class MyView < Grsx::PhlexRuntime
  def initialize(greeting:)
    @greeting = greeting
  end
end
```

## Development

```
bundle install
bundle exec rspec
```

Run against all supported Rails versions:

```
bundle exec appraisal rspec
```

When updating dependency versions in gemspec:

```
bundle exec appraisal install
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/gatopan/grsx.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
