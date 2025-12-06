# Template Block Capture Research

## Summary

Template::EmbeddedPerl supports passing anonymous subs to helpers that capture
template content. This enables ergonomic multi-line content blocks.

## How It Works

When you write:
```html
<%= helper("arg", sub { %>
  <p>Template content here</p>
<% }) %>
```

Template::EmbeddedPerl:
1. Uses PPI to detect the unclosed `sub {` block
2. Injects `my $_O = ""` at the start of the sub body
3. Template content inside gets appended to `$_O`
4. At the closing `}`, injects `raw($_O);` to return captured content
5. The helper receives a CODE ref that returns rendered HTML when called

## Argument Passing

Helpers can pass arguments to the coderef:

```perl
# In helper:
my $result = $code->($view, $extra_data);

# In template (traditional @_):
<%= helper("arg", sub { %>
<% my ($view, $data) = @_; %>
  <p><%= $data->{name} %></p>
<% }) %>

# In template (with signatures - requires preamble):
<%= helper("arg", sub ($view, $data) { %>
  <p><%= $data->{name} %></p>
<% }) %>
```

## Enabling Signatures in Templates

Add to Template::EmbeddedPerl constructor:
```perl
preamble => 'use experimental "signatures";'
```

## Benefits

1. **Multi-line content is natural** - No escaping quotes, proper syntax highlighting
2. **Access to template syntax** - Can use `<%= %>` inside blocks
3. **Arguments provide context** - Blocks can receive view, form builders, etc.
4. **Consistent with other frameworks** - Similar to Rails, Phoenix, Mojolicious

## Current State in PAGI::Simple::View

- `content_for` - Only accepts string, not coderef
- `block` - Only accepts string, not coderef
- `include` - Does not support block wrapping
- No `capture` helper for generic content capture
- Signatures not enabled in template sandbox
