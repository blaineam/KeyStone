import XCTest
@testable import Keystone

final class CodeFormatterTests: XCTestCase {
    // MARK: JSON

    func testJSONPrettifyAndMinifyRoundTrip() {
        let minified = #"{"name":"x","list":[1,2,{"a":null}],"empty":{},"arr":[],"ok":true}"#
        let pretty = CodeFormatter.format(minified, language: .json, operation: .prettify)!
        XCTAssertEqual(pretty, """
        {
          "name": "x",
          "list": [
            1,
            2,
            {
              "a": null
            }
          ],
          "empty": {},
          "arr": [],
          "ok": true
        }

        """)
        XCTAssertEqual(CodeFormatter.format(pretty, language: .json, operation: .minify), minified)
        XCTAssertEqual(CodeFormatter.format(pretty, language: .json, operation: .prettify), pretty, "idempotent")
    }

    func testJSONPreservesKeyOrderAndStringsWithBraces() {
        let input = #"{"z":"{not json}","a":"x\"y"}"#
        let pretty = CodeFormatter.format(input, language: .json, operation: .prettify)!
        XCTAssertTrue(pretty.range(of: "\"z\"")!.lowerBound < pretty.range(of: "\"a\"")!.lowerBound)
        XCTAssertEqual(CodeFormatter.format(pretty, language: .json, operation: .minify), input)
    }

    func testJSONCommentsSurviveMinifyRemovesThem() {
        let input = "{\n  // id\n  \"id\": 1 /* trailing */\n}\n"
        XCTAssertEqual(CodeFormatter.format(input, language: .json, operation: .minify), #"{"id":1}"#)
        let pretty = CodeFormatter.format(input, language: .json, operation: .prettify)!
        XCTAssertTrue(pretty.contains("// id"))
        XCTAssertTrue(pretty.contains("/* trailing */"))
    }

    // MARK: CSS

    func testCSSPrettifyAndMinify() {
        let input = "a{color:red;margin:0 auto}@media (max-width:600px){.x,.y{display:none;}}/* c */"
        let pretty = CodeFormatter.format(input, language: .css, operation: .prettify)!
        XCTAssertEqual(pretty, """
        a {
          color: red;
          margin: 0 auto;
        }

        @media (max-width:600px) {
          .x,
          .y {
            display: none;
          }
        }

        /* c */

        """)
        XCTAssertEqual(CodeFormatter.format(pretty, language: .css, operation: .minify), "a{color:red;margin:0 auto}@media (max-width:600px){.x,.y{display:none}}")
        XCTAssertEqual(CodeFormatter.format(pretty, language: .css, operation: .prettify), pretty, "idempotent")
    }

    func testCSSKeepsURLsAndStrings() {
        let input = "a{background:url(data:image/png;base64,AAA{}) ; content:\"{ ; }\"}"
        let pretty = CodeFormatter.format(input, language: .css, operation: .prettify)!
        XCTAssertTrue(pretty.contains("url(data:image/png;base64,AAA{})"))
        XCTAssertTrue(pretty.contains("content: \"{ ; }\""))
    }

    // MARK: HTML / XML

    func testHTMLPrettify() {
        let input = "<!DOCTYPE html><html><head><title>T</title><style>body{margin:0}</style></head><body><div class=\"a\"><p>Hello <b>world</b> again</p><img src=\"x.png\"><ul><li>one</li><li>two</li></ul></div><script>if(a<b){x()}</script></body></html>"
        let pretty = CodeFormatter.format(input, language: .html, operation: .prettify)!
        XCTAssertEqual(pretty, """
        <!DOCTYPE html>
        <html>
          <head>
            <title>T</title>
            <style>
              body{margin:0}
            </style>
          </head>
          <body>
            <div class="a">
              <p>Hello <b>world</b> again</p>
              <img src="x.png">
              <ul>
                <li>one</li>
                <li>two</li>
              </ul>
            </div>
            <script>
              if(a<b){x()}
            </script>
          </body>
        </html>

        """)
    }

    func testHTMLMinifyKeepsInlineSpacingAndScripts() {
        let input = """
        <div>
          <p>Hello <b>world</b> again</p>
          <!-- gone -->
          <script>
            var a = 1;
          </script>
        </div>
        """
        let minified = CodeFormatter.format(input, language: .html, operation: .minify)!
        XCTAssertEqual(minified, "<div><p>Hello <b>world</b> again</p><script>var a = 1;</script></div>")
    }

    func testXMLPrettify() {
        let input = "<?xml version=\"1.0\"?><plist><dict><key>a</key><string>b</string><array/></dict></plist>"
        let pretty = CodeFormatter.format(input, language: .xml, operation: .prettify)!
        XCTAssertEqual(pretty, """
        <?xml version="1.0"?>
        <plist>
          <dict>
            <key>a</key>
            <string>b</string>
            <array/>
          </dict>
        </plist>

        """)
    }

    func testUnsupportedLanguage() {
        XCTAssertNil(CodeFormatter.format("let a = 1", language: .swift, operation: .prettify))
        XCTAssertFalse(CodeFormatter.supports(.swift))
        XCTAssertTrue(CodeFormatter.supports(.javascript))
        XCTAssertTrue(CodeFormatter.supports(.typescript))
    }

    // MARK: - JavaScript / TypeScript

    private let program = """
    function greet(name){if(!name){return "hello"}
    const items=[1,2,3].map(x=>x*2);return `hi ${name}: ${items.join(", ")}`}
    class Counter{constructor(){this.n=0}
    inc(){this.n+=1;return this}}
    """

    func testJavaScriptPrettifyIsIdempotent() {
        let pretty = CodeFormatter.format(program, language: .javascript, operation: .prettify)!
        XCTAssertEqual(pretty, """
        function greet(name) {
          if (!name) {
            return "hello"
          }
          const items = [1, 2, 3].map(x => x * 2);
          return `hi ${name}: ${items.join(", ")}`
        }
        class Counter {
          constructor() {
            this.n = 0
          }
          inc() {
            this.n += 1;
            return this
          }
        }

        """)
        XCTAssertEqual(CodeFormatter.format(pretty, language: .javascript, operation: .prettify), pretty, "idempotent")
    }

    func testJavaScriptPrettifyHonoursIndent() {
        let pretty = CodeFormatter.format("if(a){b()}", language: .javascript, operation: .prettify, indent: "\t")!
        XCTAssertEqual(pretty, "if (a) {\n\tb()\n}\n")
        let four = CodeFormatter.format("if(a){b()}", language: .javascript, operation: .prettify, indent: "    ")!
        XCTAssertEqual(four, "if (a) {\n    b()\n}\n")
    }

    func testJavaScriptMinifyRoundTrips() {
        let pretty = CodeFormatter.format(program, language: .javascript, operation: .prettify)!
        let minified = CodeFormatter.format(pretty, language: .javascript, operation: .minify)!
        XCTAssertFalse(minified.contains("\n"))
        XCTAssertLessThan(minified.count, pretty.count)
        XCTAssertTrue(minified.contains("greet"), "identifiers are kept")
        XCTAssertEqual(CodeFormatter.format(minified, language: .javascript, operation: .prettify), pretty,
                       "minified program prettifies back to the original prettified text")
    }

    func testJavaScriptMinifyDropsComments() {
        let minified = CodeFormatter.format("// top\nconst a = 1; /* mid */ const b = 2;", language: .javascript, operation: .minify)!
        XCTAssertFalse(minified.contains("top"))
        XCTAssertFalse(minified.contains("mid"))
        XCTAssertTrue(minified.contains("const a=1"))
    }

    func testJavaScriptRegexAndTemplateLiteralsSurvive() {
        let input = "const re=/a\\/b{2}\\s+\"x\"/gi;const t=`line1\n  ${re.source}  {not: code}\n`;export{re,t};"
        let pretty = CodeFormatter.format(input, language: .javascript, operation: .prettify)!
        XCTAssertTrue(pretty.contains("/a\\/b{2}\\s+\"x\"/gi"), pretty)
        XCTAssertTrue(pretty.contains("`line1\n  ${re.source}  {not: code}\n`"), "template literal body is untouched")
        let minified = CodeFormatter.format(input, language: .javascript, operation: .minify)!
        XCTAssertTrue(minified.contains("/a\\/b{2}\\s+\"x\"/gi"), minified)
        // terser reprints the template on one line with the newline escaped (`\n`), which is the same string.
        XCTAssertTrue(minified.contains("`line1\\n  ${re.source}  {not: code}\\n`"), minified)
    }

    func testTypeScriptPrettifyKeepsTypes() {
        let input = "interface User{id:number;name?:string}\nfunction find<T extends User>(xs:T[],id:number):T|undefined{return xs.find(x=>x.id===id)}\nenum Mode{A=1,B}\nconst u=find<User>([],1) as User;"
        let pretty = CodeFormatter.format(input, language: .typescript, operation: .prettify)!
        XCTAssertTrue(pretty.contains("interface User {"), pretty)
        XCTAssertTrue(pretty.contains("id: number;"), pretty)
        XCTAssertTrue(pretty.contains("name ? : string") || pretty.contains("name?: string"), pretty)
        XCTAssertTrue(pretty.contains("xs: T[]"), pretty)
        XCTAssertTrue(pretty.contains("): T | undefined {"), pretty)
        XCTAssertTrue(pretty.contains("enum Mode {"), pretty)
        XCTAssertTrue(pretty.contains("as User"), pretty)
        XCTAssertEqual(CodeFormatter.format(pretty, language: .typescript, operation: .prettify), pretty, "idempotent")
    }

    func testTypeScriptMinifyIsRefused() {
        XCTAssertNil(CodeFormatter.format("const a: number = 1;", language: .typescript, operation: .minify))
    }

    func testJavaScriptSyntaxErrorMinifyReturnsNil() {
        XCTAssertNil(CodeFormatter.format("function (", language: .javascript, operation: .minify))
    }

    func testJavaScriptOversizeInputReturnsNil() {
        let big = String(repeating: "var a = 1;\n", count: (JavaScriptFormatter.maxInputBytes / 11) + 1)
        XCTAssertGreaterThan(big.utf8.count, JavaScriptFormatter.maxInputBytes)
        XCTAssertNil(CodeFormatter.format(big, language: .javascript, operation: .prettify))
        XCTAssertNil(CodeFormatter.format(big, language: .javascript, operation: .minify))
    }
}
