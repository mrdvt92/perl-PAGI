# PAGI::Simple UTF-8 Demo

Round-trip UTF-8 handling using PAGI::Simple routing plus the built-in UTF-8 helpers.

## Quick Start
- Run: `pagi-server --app examples/simple-13-utf8/app.pl --port 5000`
- Open `http://localhost:5000/` in a browser and click the sample links or submit the forms.
- CLI check: `curl 'http://localhost:5000/?text=%E2%9D%A4'` or `curl -X POST -d 'text=caf%C3%A9' http://localhost:5000/`

## What It Shows
- Path params are already UTF-8 decoded (`/echo/:text`) per the PAGI spec.
- Query and form params are automatically UTF-8 decoded with U+FFFD replacement; raw bytes remain available via `raw_query_param`/`raw_body_param`, and strict errors via `strict => 1`.
- Responses use the `html`/`send_utf8` helpers, which encode to UTF-8 and set `content-length` from the byte size.
- The page displays character count, UTF-8 byte count, and codepoints so you can spot encoding issues quickly.
