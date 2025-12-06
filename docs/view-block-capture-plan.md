# Block Capture Enhancement Plan

## Overview

Enhance PAGI::Simple::View to support coderef/block capture for template helpers,
enabling more ergonomic multi-line content definitions.

---

## Step 1: Add prepend Configuration Option

**Goal:** Allow users to add custom Perl code to template compilation preamble.
This enables opt-in features like signatures without breaking older Perls.

### Changes:
- Add `prepend` option to View constructor (default: '')
- Pass user's prepend to Template::EmbeddedPerl after our internal prepend
- Document how to enable signatures: `prepend => 'use experimental "signatures";'`

### Files to modify:
- `lib/PAGI/Simple/View.pm`

### Tests:
- Test default behavior (no prepend) still works
- Test custom prepend is applied
- Test signatures work when enabled via prepend

### Documentation:
- Add `prepend` to constructor options
- Add example showing how to enable signatures

---

## Step 2: Update content_for to Accept Coderef

**Goal:** Allow block syntax for defining named content.

### Current behavior:
```html
<% content_for('scripts', '<script>...</script>') %>
```

### New behavior (also support):
```html
<% content_for('scripts', sub { %>
  <script src="app.js"></script>
  <script>
    initApp();
  </script>
<% }) %>
```

### Changes:
- Update `content_for` helper in `_get_engine_helpers`
- Check if second arg is CODE ref
- If CODE, call it with `($view)` and use result
- If string, use directly (backward compatible)

### Files to modify:
- `lib/PAGI/Simple/View.pm`

### Tests:
- String argument still works
- Coderef argument captures template content
- Coderef receives $view argument
- Appending behavior preserved with coderef

### Documentation:
- Update content_for docs with block syntax examples

---

## Step 3: Update block to Accept Coderef

**Goal:** Same as content_for but for replacing (not appending).

### New behavior:
```html
<% block('sidebar', sub { %>
  <nav>
    <%= include('_nav_items') %>
  </nav>
<% }) %>
```

### Changes:
- Update `block` helper in `_get_engine_helpers`
- Check if second arg is CODE ref
- If CODE, call with `($view)` and use result

### Files to modify:
- `lib/PAGI/Simple/View.pm`

### Tests:
- String argument still works
- Coderef argument captures template content
- Replaces (not appends) behavior preserved

### Documentation:
- Update block docs with block syntax examples

---

## Step 4: Add capture Helper

**Goal:** Generic helper to capture template content as a string variable.

### Usage:
```html
<% my $card_html = capture(sub { %>
  <div class="card">
    <h2><%= $v->title %></h2>
    <p><%= $v->body %></p>
  </div>
<% }); %>

<!-- Use it multiple times -->
<%= raw($card_html) %>
<%= raw($card_html) %>
```

### Changes:
- Add `capture` helper to `_get_engine_helpers`
- Takes coderef, calls it, returns captured string

### Files to modify:
- `lib/PAGI/Simple/View.pm`

### Tests:
- Captures template content
- Returns string (not safe string, user decides escaping)
- Can be stored in variable and reused

### Documentation:
- Add capture to TEMPLATE HELPERS section

---

## Implementation Order

1. **Step 1** - Add prepend config option
2. **Step 2** - content_for with coderef
3. **Step 3** - block with coderef
4. **Step 4** - capture helper

## Test File Structure

Create: `t/view/03-block-capture.t`
- Test signatures in templates
- Test content_for with string (existing)
- Test content_for with coderef (new)
- Test block with string (existing)
- Test block with coderef (new)
- Test capture helper (new)
- Test $view argument available in blocks

## Documentation Updates

Update `lib/PAGI/Simple/View.pm` POD:
- TEMPLATE SYNTAX: Note signature support
- content_for: Add block syntax example
- block: Add block syntax example
- capture: New section

---

## Completed Improvements

### Views Configuration in Constructor ✓

Views can now be configured in the `PAGI::Simple->new()` constructor:

```perl
# Shorthand - directory relative to app file
my $app = PAGI::Simple->new(
    name  => 'My App',
    views => 'templates',
);

# Full syntax with options
my $app = PAGI::Simple->new(
    name  => 'My App',
    views => {
        directory => 'templates',
        prepend   => 'use experimental "signatures";',
        cache     => 0,
    },
);

# Default ./templates directory
my $app = PAGI::Simple->new(views => undef);
```

**Features:**
- Relative paths resolved from the file creating the app (not cwd)
- Both shorthand string and hashref syntax supported
- `->views()` method still works and overrides constructor config
- Backward compatible with existing `->views($dir, \%opts)` calls

### Cleaner $app->views() API ✓

The `->views()` method now supports flat named params:
```perl
$app->views('templates', preamble => '...', cache => 0);
```

While remaining backward compatible with hashref:
```perl
$app->views('templates', { preamble => '...', cache => 0 });
```
