-- url-strip-images.lua
-- Applied by 2pdf.sh ONLY when the source is an http(s) URL.
--
-- Rationale: web pages reference images that are almost always chrome (site
-- logos, nav icons, coat-of-arms) rather than reading content, and they
-- routinely break a pandoc -> xelatex PDF build:
--   * SVG/SVGZ images need `rsvg-convert` (librsvg) to embed; without it the
--     whole build hard-fails.
--   * Relative image paths don't resolve from the local temp copy of the page,
--     so xelatex aborts with "file does not exist".
-- For a Boox reading PDF the article text is what matters, so we drop images
-- to make the conversion reliable. Local .html files are NOT affected — their
-- images are assumed intentional and resolvable.
function Image(_el)
  return {}
end
