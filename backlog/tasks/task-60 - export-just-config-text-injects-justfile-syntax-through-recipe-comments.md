---
id: TASK-60
title: 'export-just: config text injects justfile syntax through recipe comments'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T23:12:00Z'
updated_date: '2026-11-09T23:22:00Z'
labels:
  - audit
  - security
  - export-just
dependencies: []
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
format_recipe interpolated job name, stage, tags, Depends: names and the header's --entry/--output paths unescaped into '#' comment lines. A newline ends the comment: a job named "evil\nboom:\n    touch X" adds a recipe, and a tag "t\npwn := `touch X`" adds a top-level assignment whose backtick just evaluates when ANY recipe runs (also at --evaluate). Fix the class: one comment_text helper escaping every control character (and U+2028/2029, backslash) for every comment interpolation; assert every recipe name written is a just identifier; shell_quote gets one home (lib/shell_quote.rb).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Both reviewer repros (newline job name, newline tag) are red on the parent and green after
- [x] #2 Seeded property spec: random hostile job names/stages/tags/environment names/variable values give exactly the expected recipe set in just --list, and --list/--evaluate/running a recipe touch no sentinel
- [x] #3 Every non-body interpolation in the generated justfile goes through comment_text or is a validated identifier; audit recorded in notes
- [x] #4 shell_quote has one definition and one spec
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in cbd81a5. Class fix: config text reaches the justfile only as (1) recipe body lines (indented line by line, {{ doubled, values ShellQuote-quoted, scripts in a quoted heredoc - unchanged), (2) recipe names, asserted against RECIPE_NAME_PATTERN before writing, (3) comment text via comment_text (escapes [[:cntrl:]], U+0085/2028/2029 and backslash in Ruby escape form). Audit of every interpolation: header mode/flag constants; Generated = Time; Source and --output -> comment_text; recipe comment name/Stage/Tags/Depends -> comment_text; signature -> sanitised + asserted; body: export KEY (KEY_PATTERN [A-Za-z0-9_]+ enforced by JobEnvironment), values/project dir/trigger echo -> ShellQuote, after_script timeout Numeric, scripts heredoc with delimiter-line check. Lone \r verified harmless in just 1.51 (body and comment). shell_quote: one home lib/shell_quote.rb (refuses NUL), one bash round-trip spec. Bite: both reviewer repros reproduced on 4c2f318 (pwned files created, extra recipe 'boom'); the 4 new injection examples are red on the parent and green after; each comment_text call site mutated away in turn -> killed. Gates: 902/0/47, just test exit 0, e2e green. Not covered: stderr warnings print job names unescaped (terminal escape sequences, not justfile injection); log_warning is outside the justfile.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
export-just no longer lets config text (job names, stages, tags, Depends names, --entry/--output paths) break out of '#' comment lines: one comment_text helper escapes control characters at every comment site, recipe names are asserted identifiers, and shell_quote has one home. Both reviewer repros (extra recipe via newline job name; top-level backtick assignment via newline tag running on any recipe) are red on the parent and green after; a seeded property spec covers hostile names/stages/tags/environments/values with sentinel checks for --list/--evaluate/run.
<!-- SECTION:FINAL_SUMMARY:END -->
