//
//  JavaScriptLanguageSupport.swift
//  Fabric
//
//  Created by Codex on 3/14/26.
//

import LanguageSupport

private let javaScriptReservedOperators = [
    ".", ",", ";", ":", "?", "=>",
    "=", "+", "-", "*", "/", "%", "**",
    "+=", "-=", "*=", "/=", "%=", "**=",
    "==", "===", "!=", "!==", "<", ">", "<=", ">=",
    "&&", "||", "!",
    "&", "|", "^", "~", "<<", ">>", ">>>",
    "&=", "|=", "^=", "<<=", ">>=", ">>>=",
]

private let javaScriptReservedIdentifiers = [
    "arguments", "async", "await", "break", "case", "catch", "class", "const", "continue",
    "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "false",
    "finally", "for", "function", "if", "implements", "import", "in", "instanceof",
    "interface", "let", "new", "null", "package", "private", "protected", "public",
    "return", "static", "super", "switch", "this", "throw", "true", "try", "typeof",
    "undefined", "var", "void", "while", "with", "yield",
    "Array", "BigInt", "Boolean", "Date", "Error", "JSON", "Map", "Math", "Number",
    "Object", "Promise", "RegExp", "Set", "String", "Symbol", "WeakMap", "WeakSet",
    "console", "globalThis",
]

extension LanguageConfiguration
{
    public static func javaScriptLanguage(_ languageService: LanguageService? = nil) -> LanguageConfiguration
    {
        let stringRegex = try? Regex<Substring>(#""(?:\\.|[^"\\])*+"|'(?:\\.|[^'\\])*+'|`(?:\\.|[^`\\])*+`"#)
        let numberRegex = try? Regex<Substring>(#"-?(?:0[xX][0-9A-Fa-f]+|0[bB][01]+|0[oO][0-7]+|\d+\.\d+(?:[eE][+-]?\d+)?|\d+[eE][+-]?\d+|\d+)"#)
        let identifierRegex = try? Regex<Substring>(#"[A-Za-z_$][A-Za-z0-9_$]*"#)
        let operatorRegex = try? Regex<Substring>(#"[+\-*/%=!<>|&^~?:.,;]+"#)

        return LanguageConfiguration(
            name: "JavaScript",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            stringRegex: stringRegex,
            characterRegex: nil,
            numberRegex: numberRegex,
            singleLineComment: "//",
            nestedComment: (open: "/*", close: "*/"),
            identifierRegex: identifierRegex,
            operatorRegex: operatorRegex,
            reservedIdentifiers: javaScriptReservedIdentifiers,
            reservedOperators: javaScriptReservedOperators,
            languageService: languageService
        )
    }
}
