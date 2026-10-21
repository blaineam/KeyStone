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
        XCTAssertFalse(CodeFormatter.supports(.javascript))
    }
}
