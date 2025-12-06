# PAGI::Simple Views Example

Demonstrates the template rendering system with layouts, partials, and variable interpolation.

## Quick Start

**1. Start the server:**

```bash
pagi-server --app examples/simple-15-views/app.pl --port 5000
```

**2. Open in browser:**

Visit http://localhost:5000/

## Features

- Template rendering with `$c->render('template', %vars)`
- Layout system with `extends('layouts/default')`
- Partial templates with `include('_partial', %vars)`
- Variable interpolation with `<%= $v->{name} %>`
- Auto-escaping (XSS protection)

## Routes

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Home page with layout |
| GET | `/greet/:name` | Greet by name |
| GET | `/with-partial` | Demonstrates partial includes |
| GET | `/fragment` | Returns fragment without layout |

## Template Syntax

Templates use `Template::EmbeddedPerl` syntax:

```html
<%# This is a comment %>
<%= $v->{variable} %>       <%# Output with auto-escaping %>
<%= raw($v->{html}) %>      <%# Output without escaping %>
<% if ($v->{show}) { %>     <%# Perl code block %>
    <p>Shown!</p>
<% } %>
```

## Directory Structure

```
simple-15-views/
├── app.pl
├── README.md
└── templates/
    ├── layouts/
    │   └── default.html.ep    # Main layout
    ├── index.html.ep          # Home page
    ├── greet.html.ep          # Greet page
    ├── with_partial.html.ep   # Partial demo
    └── _item.html.ep          # Partial template
```

## Code Highlights

### Configure Views

```perl
use File::Basename;
use File::Spec;
my $script_dir = File::Basename::dirname(File::Spec->rel2abs(__FILE__));
$app->views("$script_dir/templates");
```

### Render a Template

```perl
$app->get('/' => sub ($c) {
    $c->render('index',
        title => 'Welcome',
        message => 'Hello!',
    );
});
```

### Layout Template (layouts/default.html.ep)

```html
<!DOCTYPE html>
<html>
<head><title><%= $v->{title} %></title></head>
<body>
    <%= content() %>
</body>
</html>
```

### Page Template (index.html.ep)

```html
<% extends('layouts/default') %>
<h1><%= $v->{title} %></h1>
<p><%= $v->{message} %></p>
```

### Include Partial

```html
<% for my $item (@{$v->{items}}) { %>
    <%= include('_item', item => $item) %>
<% } %>
```
