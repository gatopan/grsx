# A Ruby template language inspired by JSX

[![Build Status](https://github.com/patbenatar/grsx/actions/workflows/main.yml/badge.svg?branch=master)](https://github.com/patbenatar/grsx/actions?query=branch%3Amaster)

* [Getting Started](#getting-started-with-rails)
* [Template Syntax](#template-syntax)
* [Components](#components)
  * [`Grsx::Component`](#grsxcomponent)
  * [Usage with any component library](#usage-with-any-component-library)
* [Fragment caching in Rails](#fragment-caching-in-rails)
* [Advanced](#advanced)
  * [Component resolution](#component-resolution)
  * [AST Transforms](#ast-transforms)
  * [Usage outside of Rails](#usage-outside-of-rails)

## Manifesto

Love JSX and component-based frontends, but sick of paying the costs of SPA development? Grsx brings the elegance of JSX—operating on HTML elements and custom components with an interchangeable syntax—to the world of Rails server-rendered apps.

Combine this with CSS Modules in your Webpacker PostCSS pipeline and you'll have a first-class frontend development experience while maintaining the development efficiency of Rails.

_But what about Javascript and client-side behavior?_ You probably don't need as much of it as you think you do. See how far you can get with layering RailsUJS, vanilla JS, Turbolinks, and/or StimulusJS onto your server-rendered components. I think you'll be pleasantly surprised with the modern UX you're able to build while writing and maintaining less code.

## Example

Use your custom Ruby class components from `.rsx` templates just like you would React components in JSX:

```jsx
<body>
  <Hero size="fullscreen" {**splat_some_attributes}>
    <h1>Hello {@name}</h1>
    <p>Welcome to grsx, marrying the nice parts of React templating with the development efficiency of Rails server-rendered apps.</p>
    <Button to={about_path}>Learn more</Button>
  </Hero>
</body>
```

after defining them in Ruby:

```ruby
class HeroComponent < Grsx::Component # or use ViewComponent, or another component lib
  def setup(size:)
    @size = size
  end
end

class ButtonComponent < Grsx::Component
  def setup(to:)
    @to = to
  end
end
```

with their accompying template files (also can be `.rsx`!), scoped scss files, JS and other assets (not shown).

## Getting Started (with Rails)

Add it to your Gemfile and `bundle install`:

```ruby
gem "grsx"
```

_From 1.0 onward, we only support Rails 6. If you're using Rails 5, use the 0.x releases._

_Not using Rails? See "Usage outside of Rails" below._

Create your first component at `app/components/hello_world_component.rb`:

```ruby
class HelloWorldComponent < Grsx::Component
  def setup(name:)
    @name = name
  end
end
```

With a template `app/components/hello_world_component.rsx`:

```jsx
<div>
  <h1>Hello {@name}</h1>
  {content}
</div>
```

Add a controller, action, route, and `rsx` view like `app/views/hello_worlds/index.rsx`:

```jsx
<HelloWorld name="Nick">
  <p>Welcome to the world of component-based frontend development in Rails!</p>
</HelloWorld>
```

Fire up `rails s`, navigate to your route, and you should see Grsx in action!

## Template Syntax

You can use Ruby code within brackets:

```jsx
<p class={@dynamic_class}>
  Hello {"world".upcase}
</p>
```

You can splat a hash into attributes:

```jsx
<div {**{class: "myClass"}} {**@more_attrs}></div>
```

You can use HTML or component tags within expressions. e.g. to conditionalize a template:

```jsx
<div>
  {some_boolean && <h1>Welcome</h1>}
  {another_boolean ? <p>Option One</p> : <p>Option Two</p>}
</div>
```

Or in loops:

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

Pass a tag to a component as an attribute:

```jsx
<Hero title={<h1>Hello World</h1>}>
  Content here...
</Hero>
```

Or pass a lambda as an attribute, that when called returns a tag:

```jsx
<Hero title={-> { <h1>Hello World</h1> }}>
  Content here...
</Hero>
```

_Note that when using tags inside blocks, the block must evaluate to a single root element. Grsx behaves similar to JSX in this way. E.g.:_

```
# Do
-> { <span><i>Hello</i> World</span> }

# Don't
-> { <i>Hello</i> World }
```

Start a line with `#` to leave a comment:

```jsx
# Private note to self that won't be rendered in the final HTML
```

## Components

You can use Ruby classes as components alongside standard HTML tags:

```jsx
<div>
  <PageHeader title="Welcome" />
  <PageBody>
    <p>To the world of custom components</p>
  </PageBody>
</div>
```

By default, Grsx will resolve `PageHeader` to a Ruby class called `PageHeaderComponent` and render it with the view context, attributes, and its children: `PageHeaderComponent.new(self, title: "Welcome").render_in(self, &block)`. This behavior is customizable, see "Component resolution" below.

### `Grsx::Component`

We ship with a component superclass that integrates nicely with Rails' ActionView and the controller rendering context. You can use it to easily implement custom components in your Rails app:

```ruby
# app/components/page_header_component.rb
class PageHeaderComponent < Grsx::Component
  def setup(title:)
    @title = title
  end
end
```

By default, we'll look for a template file in the same directory as the class and with a matching filename:

```jsx
// app/components/page_header_component.rsx
<h1>{@title}</h1>
```

Your components and their templates run in the same context as traditional Rails views, so you have access to all of the view helpers you're used to as well as any custom helpers you've defined in `app/helpers/` or via `helper_method` in your controller.

#### Template-less components

If you'd prefer to render your components entirely from Ruby, you can do so by implementing `#call`:

```ruby
class PageHeaderComponent < Grsx::Component
  def setup(title:)
    @title = title
  end

  def call
    tag.h1 @title
  end
end
```

#### Context

`Grsx::Component` implements a similar notion to React's Context API, allowing you to pass data through the component tree without having to pass props down manually.

Given a template:

```jsx
<Form>
  <TextField field={:title} />
</Form>
```

The form component can use Rails `form_for` and then pass the `form` builder object down to any field components using context:

```ruby
class FormComponent < Grsx::Component
  def setup(form_object:)
    @form_object = form_object
  end

  def call
    form_for @form_object do |form|
      create_context(:form, form)
      content
    end
  end
end

class TextFieldComponent < Grsx::Component
  def setup(field:)
    @field = field
    @form = use_context(:form)
  end

  def call
    @form.text_field @field
  end
end
```

#### Usage with ERB

We recommend using `Grsx::Component` with the rsx template language, but if you prefer ERB... a component's template can be `.html.erb` and you  can render a component from ERB like so:

Rails 6.1:

```erb
<%= render PageHeaderComponent.new(self, title: "Welcome") do %>
  <p>Children...</p>
<% end >
```

Rails 6.0 or earlier:

```erb
<%= PageHeaderComponent.new(self, title: "Welcome").render_in(self) %>
```

### Usage with any component library

You can use the rsx template language with other component libraries like Github's view_component. You just need to tell Grsx how to render the component:

```ruby
# config/initializers/grsx.rb
Grsx.configure do |config|
  config.component_rendering_templates = {
    children: "{capture{%{children}}}",
    component: "::%{component_class}.new(%{view_context},%{kwargs}).render_in%{children_block}"
  }
end
```

## Fragment caching in Rails

`.rsx` templates integrate with Rails fragment caching, automatically cachebusting when the template or its render dependencies change.

If you're using `Grsx::Component`, you can further benefit from component cachebusting where the fragment cache will be busted if any dependent component's template _or_ class definition changes.

And you can use `<Grsx.Cache>`, a convenient wrapper for the Rails fragment cache:

```rsx
<Grsx.Cache key={...}>
  <p>Fragment here...</p>
  <MyButton />
</Grsx.Cache>
```

## Advanced

### Component resolution

By default, Grsx resolves component tags to Ruby classes named `#{tag}Component`, e.g.:

* `<PageHeader />` => `PageHeaderComponent`
* `<Admin.Button />` => `Admin::ButtonComponent`

You can customize this behavior by providing a custom resolver:

```ruby
# config/initializers/grsx.rb
Grsx.configure do |config|
  config.element_resolver = MyResolver.new
end
```

Where `MyResolver` implements the following API:

* `component?(name: string, template: Grsx::Template) => Boolean`
* `component_class(name: string, template: Grsx::Template) => T`

See `lib/grsx/component_resolver.rb` for an example.

#### Auto-namespacing

Want to namespace your components but sick of typing `Admin.` in front of every component call? Grsx's default `ComponentResolver` implementation has an option for that:

```ruby
# config/initializers/grsx.rb
Grsx.configure do |config|
  config.element_resolver.component_namespaces = {
    Rails.root.join("app", "views", "admin") => %w[Admin],
    Rails.root.join("app", "components", "admin") => %w[Admin]
  }
end
```

Now any calls to `<Button>` made from `.rsx` views within `app/views/admin/` or from component templates within `app/components/admin/` will first check for `Admin::ButtonComponent` before `ButtonComponent`.

### AST Transforms

You can hook into Grsx's compilation process to mutate the abstract syntax tree. This is both useful and dangerous, so use with caution.

An example use case is automatically scoping CSS class names if you're using something like CSS Modules. Here's an oversimplified example of this:

```ruby
# config/initializers/grsx.rb
Grsx.configure do |config|
  config.transforms.register(Grsx::Nodes::HTMLAttr) do |node, context|
    if node.name == "class"
      class_list = node.value.split(" ")
      node.value.content = scope_names(class_list, scope: context.template.identifier)
    end
  end
end
```

### Usage outside of Rails

Grsx compiles your template into ruby code, which you can then execute in any context you like. Subclass `Grsx::Runtime` to add methods and instance variables that you'd like to make available to your template.

```ruby
class MyRuntime < Grsx::Runtime
  def initialize
    super
    @an_ivar = "Ivar value"
  end

  def a_method
    "Method value"
  end
end

Grsx.evaluate("<p class={a_method}>{@an_ivar}</p>", MyRuntime.new)
```

## Development

```
docker-compose build
docker-compose run grsx bin/test
```

Or auto-run tests with guard if you prefer:

```
docker-compose run grsx guard
```

If you want to run against the supported versions of Rails, use
Appraisal:

```
docker-compose run grsx bundle exec appraisal bin/test
```

When updating dependency versions in gemspec, you also need to regenerate the appraisal gemspecs with:

```
docker-compose run grsx bundle exec appraisal install
```

## Debugging TemplatePath methods being called
When a new version of Rails is released, we need to check what methods are being
called on `Grsx::Component::TemplatePath` to make sure we always return
a TemplatePath, not a string due to how we handle `TemplatePath`s
internally.

To list all methods being called, enable `GRSX_TEMPLATE_PATH_DEBUG` and
run tests:

```
docker-compose run -e GRSX_TEMPLATE_PATH_DEBUG=1 grsx bundle exec appraisal bin/test
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/patbenatar/grsx. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/patbenatar/grsx/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Grsx project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/patbenatar/grsx/blob/master/CODE_OF_CONDUCT.md).
