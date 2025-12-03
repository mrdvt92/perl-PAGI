# CPAN Module Migration Plan

## Overview

Replace custom PAGI::Simple modules with well-tested CPAN alternatives:
1. **Priority 1**: Cookie.pm → Cookie::Baker
2. **Priority 2**: Logger.pm → Apache::LogFormat::Compiler

## Priority 1: Replace Cookie.pm with Cookie::Baker

### Background
- **Cookie::Baker** provides `crush_cookie()` for parsing and `bake_cookie()` for formatting
- Supports optional XS backend for 10x performance
- Well-tested, ~500k downloads/month

### Breaking Changes
- Remove relative time syntax (`+1h`, `+30d`, `+1y`) - use epoch timestamps instead
- Remove `PAGI::Simple::Cookie` class (OO instance methods)
- Direct function calls replace class methods

### Step 1.1: Add Cookie::Baker dependency
- Add `Cookie::Baker` to cpanfile
- Run tests to ensure current code still works

### Step 1.2: Create internal cookie utility module
- Create `lib/PAGI/Simple/CookieUtil.pm` as thin wrapper
- Implement `parse_cookie_header()` using `Cookie::Baker::crush_cookie()`
- Implement `format_set_cookie()` using `Cookie::Baker::bake_cookie()`
- Keep API similar to minimize changes in consuming code

### Step 1.3: Update Request.pm to use new cookie utilities
- Replace `use PAGI::Simple::Cookie` with `use PAGI::Simple::CookieUtil`
- Update `cookies()` method to use new parsing function
- Run tests

### Step 1.4: Update Context.pm to use new cookie utilities
- Replace cookie formatting calls
- Convert any relative time usage to epoch timestamps
- Update `cookie()` and `remove_cookie()` methods
- Run tests

### Step 1.5: Update Middleware::Cookie if needed
- Review and update any cookie-related middleware code
- Run tests

### Step 1.6: Update cookie tests
- Rewrite `t/simple/25-cookies.t`
- Remove tests for `parse_expiration()` relative time syntax
- Remove tests for Cookie OO instance methods
- Add tests for Cookie::Baker integration
- Ensure all cookie functionality is tested

### Step 1.7: Update example app
- Update `examples/simple-08-cookies/app.pl`
- Replace all `expires => '+30d'` with epoch timestamps (e.g., `time() + 30*24*60*60`)
- Test example app manually

### Step 1.8: Remove old Cookie.pm
- Delete `lib/PAGI/Simple/Cookie.pm`
- Update documentation in Simple.pm
- Run full test suite

## Priority 2: Replace Logger.pm with Apache::LogFormat::Compiler

### Background
- **Apache::LogFormat::Compiler** compiles format strings to Perl code for performance
- Same Apache-compatible format string syntax (`%h`, `%r`, `%s`, etc.)
- Uses POSIX::strftime::Compiler for fast timestamps

### Breaking Changes
- Remove JSON format preset (users can use custom format string if needed)
- Slight API changes in how logger is instantiated

### Step 2.1: Add Apache::LogFormat::Compiler dependency
- Add `Apache::LogFormat::Compiler` to cpanfile
- Run tests to ensure current code still works

### Step 2.2: Create new Logger implementation
- Rewrite `lib/PAGI/Simple/Logger.pm` using Apache::LogFormat::Compiler
- Keep same public API: `new()`, `log()`, `wrap_send()`
- Keep `skip` and `skip_if` options
- Implement `combined`, `common`, `tiny` presets
- Remove `json` preset

### Step 2.3: Update format specifier mapping
- Map custom specifiers to Apache::LogFormat::Compiler equivalents
- Ensure `%h`, `%t`, `%r`, `%m`, `%U`, `%q`, `%>s`, `%s`, `%b`, `%B`, `%T`, `%D` work
- Handle `%{Header}i` and `%{Header}o` for request/response headers
- Handle `%Ts` (seconds with 's' suffix) as custom extension

### Step 2.4: Update Simple.pm enable_logging
- Review and update `enable_logging()` method if needed
- Ensure Logger instantiation works with new implementation
- Run tests

### Step 2.5: Update logger tests
- Rewrite `t/simple/27-logging.t`
- Remove JSON format tests
- Add tests for Apache::LogFormat::Compiler integration
- Test all format specifiers
- Test skip/skip_if functionality

### Step 2.6: Update example app and documentation
- Update `examples/simple-10-logging/app.pl`
- Remove JSON format option comments
- Update inline documentation
- Update POD in Simple.pm regarding logging formats

### Step 2.7: Run full test suite and verify
- Run all tests: `prove -l t/`
- Verify no regressions
- Test all example apps

## Test Verification Checkpoints

After each step, run:
```bash
prove -l t/simple/25-cookies.t  # For cookie changes
prove -l t/simple/27-logging.t  # For logger changes
prove -l t/simple/             # Full simple tests
```

## Example Apps to Test

After all changes:
```bash
# Test each simple example app
perl -c examples/simple-01-hello/app.pl
perl -c examples/simple-02-forms/app.pl
perl -c examples/simple-03-websocket/app.pl
perl -c examples/simple-04-sse/app.pl
perl -c examples/simple-05-streaming/app.pl
perl -c examples/simple-06-negotiation/app.pl
perl -c examples/simple-07-uploads/app.pl
perl -c examples/simple-08-cookies/app.pl
perl -c examples/simple-09-cors/app.pl
perl -c examples/simple-10-logging/app.pl
perl -c examples/simple-11-named-routes/app.pl
perl -c examples/simple-12-mount/app.pl
```

## Rollback Plan

If issues arise:
1. Keep old Cookie.pm/Logger.pm in a backup branch
2. Revert cpanfile changes
3. Revert module changes

## Success Criteria

- [x] All 525 tests pass (reduced from 531 due to removed obsolete tests)
- [x] Cookie parsing and formatting works with Cookie::Baker
- [x] Logger works with Apache::LogFormat::Compiler
- [x] All 12 example apps compile and run
- [x] Documentation updated (POD in CookieUtil.pm, Logger.pm)
- [x] No relative time syntax in cookies (breaking change documented)
- [x] No JSON logging format (breaking change documented)
