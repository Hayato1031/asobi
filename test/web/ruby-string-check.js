// Checks how the playground's engine (ruby-engine.js) hands strings to Ruby
// without the js gem: rubyString(text) is Ruby source for the same string,
// with nothing but hex digits between its quotes. Plain Node.
//
//   node test/web/ruby-string-check.js _site/assets/ruby-engine.js
//
// Prints a JSON object (test/site_test.rb checks it and evals each
// expression in Ruby); exits 1 when the script itself cannot run.
"use strict";
const path = require("path");

const engine = require(path.resolve(process.argv[2]));
const SHAPE = /^\["[0-9a-f]*"\]\.pack\("H\*"\)\.force_encoding\("UTF-8"\)$/;

const cases = [
  "show circle(radius: 3)",
  "日本語の絵",
  "🌸 x 👩‍👩‍👧",
  "say \"hi\" and 'bye'",
  "back\\slash \\\" \\\\",
  "#{system('x')} %q{a} \"#{1}\"",
  "line 1\nline 2\r\n\ttab",
  "\"].pack(\"H*\")); system(\"x\"); [\"",
  ""
];

const result = {
  cases: cases.map((text) => {
    const expr = engine.rubyString(text);
    const hex = (/^\["([0-9a-f]*)"\]/.exec(expr) || [])[1];
    const back = hex === undefined ? null : Buffer.from(hex, "hex");
    return {
      text, expr,
      shape: SHAPE.test(expr),
      roundTrip: back !== null && back.equals(Buffer.from(text, "utf8"))
    };
  }),
  lang: ["ja", "en", "fr", '"; x', undefined].map((l) => engine.rubyLang(l))
};

console.log(JSON.stringify(result));
