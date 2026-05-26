import XCTest
@testable import Zyquo

// MARK: - SymbolExtractor Tests

final class SwiftSymbolExtractorTests: XCTestCase {
    let extractor = SwiftSymbolExtractor()

    func testExtractFunc() {
        let source = """
        func greet(name: String) -> String {
            return "Hello, \\(name)"
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        let funcs = symbols.filter { $0.kind == .function }
        XCTAssertEqual(funcs.count, 1)
        XCTAssertEqual(funcs[0].name, "greet")
        XCTAssertEqual(funcs[0].line, 1)
        XCTAssertNil(funcs[0].scope)
    }

    func testExtractClass() {
        let source = """
        public class MyViewController: UIViewController {
            var title: String = ""
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        let classes = symbols.filter { $0.kind == .class }
        XCTAssertEqual(classes.count, 1)
        XCTAssertEqual(classes[0].name, "MyViewController")
    }

    func testExtractStruct() {
        let source = """
        public struct Config: Sendable {
            let name: String
            let value: Int
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        let structs = symbols.filter { $0.kind == .struct }
        XCTAssertEqual(structs.count, 1)
        XCTAssertEqual(structs[0].name, "Config")
    }

    func testExtractEnum() {
        let source = """
        enum Direction: String, CaseIterable {
            case north, south, east, west
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        let enums = symbols.filter { $0.kind == .enum }
        XCTAssertEqual(enums.count, 1)
        XCTAssertEqual(enums[0].name, "Direction")
    }

    func testExtractProtocol() {
        let source = """
        public protocol Renderable: Sendable {
            func render() -> String
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        let protocols = symbols.filter { $0.kind == .protocol }
        XCTAssertEqual(protocols.count, 1)
        XCTAssertEqual(protocols[0].name, "Renderable")
    }

    func testExtractExtension() {
        let source = """
        extension String {
            func trimmed() -> String { self.trimmingCharacters(in: .whitespaces) }
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        let extensions = symbols.filter { $0.kind == .extension }
        XCTAssertEqual(extensions.count, 1)
        XCTAssertEqual(extensions[0].name, "String")
    }

    func testExtractVarAndLet() {
        let source = """
        public var globalVar: Int = 42
        let globalConst = "hello"
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        let vars = symbols.filter { $0.kind == .variable }
        let consts = symbols.filter { $0.kind == .constant }
        XCTAssertEqual(vars.count, 1)
        XCTAssertEqual(vars[0].name, "globalVar")
        XCTAssertEqual(consts.count, 1)
        XCTAssertEqual(consts[0].name, "globalConst")
    }

    func testExtractImport() {
        let source = """
        import Foundation
        import UIKit
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        let imports = symbols.filter { $0.kind == .import }
        XCTAssertEqual(imports.count, 2)
        XCTAssertEqual(imports[0].name, "Foundation")
        XCTAssertEqual(imports[1].name, "UIKit")
    }

    func testMethodInsideStruct() {
        let source = """
        struct Greeter {
            func greet() -> String {
                return "Hello"
            }
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        let methods = symbols.filter { $0.kind == .method }
        XCTAssertEqual(methods.count, 1)
        XCTAssertEqual(methods[0].name, "greet")
        XCTAssertEqual(methods[0].scope, "Greeter")
    }

    func testPropertyInsideClass() {
        let source = """
        class User {
            var name: String = ""
            let id: Int = 0
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        let properties = symbols.filter { $0.kind == .property }
        XCTAssertEqual(properties.count, 2)
        XCTAssertTrue(properties.contains { $0.name == "name" })
        XCTAssertTrue(properties.contains { $0.name == "id" })
    }

    func testSkipsComments() {
        let source = """
        // This is a comment
        // func notAFunction() {}
        func realFunction() {}
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        let funcs = symbols.filter { $0.kind == .function }
        XCTAssertEqual(funcs.count, 1)
        XCTAssertEqual(funcs[0].name, "realFunction")
    }

    func testAccessModifiers() {
        let source = """
        public func publicFunc() {}
        private func privateFunc() {}
        internal func internalFunc() {}
        fileprivate func fileprivateFunc() {}
        open class OpenClass {}
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.swift")
        XCTAssertTrue(symbols.contains { $0.name == "publicFunc" })
        XCTAssertTrue(symbols.contains { $0.name == "privateFunc" })
        XCTAssertTrue(symbols.contains { $0.name == "internalFunc" })
        XCTAssertTrue(symbols.contains { $0.name == "fileprivateFunc" })
        XCTAssertTrue(symbols.contains { $0.name == "OpenClass" })
    }
}

final class TypeScriptSymbolExtractorTests: XCTestCase {
    let extractor = TypeScriptSymbolExtractor()

    func testExtractFunction() {
        let source = """
        function greet(name: string): string {
            return `Hello, ${name}`;
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.ts")
        let funcs = symbols.filter { $0.kind == .function }
        XCTAssertEqual(funcs.count, 1)
        XCTAssertEqual(funcs[0].name, "greet")
    }

    func testExtractClass() {
        let source = """
        export class UserService {
            private users: User[] = [];
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.ts")
        let classes = symbols.filter { $0.kind == .class }
        XCTAssertEqual(classes.count, 1)
        XCTAssertEqual(classes[0].name, "UserService")
    }

    func testExtractInterface() {
        let source = """
        export interface Config {
            name: string;
            value: number;
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.ts")
        let interfaces = symbols.filter { $0.kind == .interface }
        XCTAssertEqual(interfaces.count, 1)
        XCTAssertEqual(interfaces[0].name, "Config")
    }

    func testExtractConst() {
        let source = """
        export const MAX_SIZE = 100;
        const handler = (req: Request) => {};
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.ts")
        let consts = symbols.filter { $0.name == "MAX_SIZE" }
        XCTAssertEqual(consts.count, 1)
        XCTAssertEqual(consts[0].kind, .constant)
        // Arrow function const
        let arrowFuncs = symbols.filter { $0.name == "handler" }
        XCTAssertEqual(arrowFuncs.count, 1)
        XCTAssertEqual(arrowFuncs[0].kind, .function)
    }

    func testExtractExportedFunction() {
        let source = """
        export async function fetchData(url: string): Promise<Data> {
            return await fetch(url);
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.ts")
        let funcs = symbols.filter { $0.kind == .function }
        XCTAssertEqual(funcs.count, 1)
        XCTAssertEqual(funcs[0].name, "fetchData")
    }

    func testExtractImport() {
        let source = """
        import { useState } from 'react';
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.ts")
        let imports = symbols.filter { $0.kind == .import }
        XCTAssertEqual(imports.count, 1)
        XCTAssertEqual(imports[0].name, "react")
    }

    func testExtractTypeAlias() {
        let source = """
        export type UserId = string;
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.ts")
        let aliases = symbols.filter { $0.kind == .typeAlias }
        XCTAssertEqual(aliases.count, 1)
        XCTAssertEqual(aliases[0].name, "UserId")
    }
}

final class PythonSymbolExtractorTests: XCTestCase {
    let extractor = PythonSymbolExtractor()

    func testExtractDef() {
        let source = """
        def hello(name):
            print(f"Hello {name}")
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.py")
        let funcs = symbols.filter { $0.kind == .function }
        XCTAssertEqual(funcs.count, 1)
        XCTAssertEqual(funcs[0].name, "hello")
    }

    func testExtractClass() {
        let source = """
        class UserModel:
            def __init__(self):
                self.name = ""

            def save(self):
                pass
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.py")
        let classes = symbols.filter { $0.kind == .class }
        XCTAssertEqual(classes.count, 1)
        XCTAssertEqual(classes[0].name, "UserModel")

        let methods = symbols.filter { $0.kind == .method }
        XCTAssertEqual(methods.count, 2)
        XCTAssertTrue(methods.allSatisfy { $0.scope == "UserModel" })
    }

    func testExtractImport() {
        let source = """
        import os
        from pathlib import Path
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.py")
        let imports = symbols.filter { $0.kind == .import }
        XCTAssertEqual(imports.count, 2)
        XCTAssertTrue(imports.contains { $0.name == "os" })
        XCTAssertTrue(imports.contains { $0.name == "pathlib" })
    }

    func testExtractAsyncDef() {
        let source = """
        async def fetch_data(url):
            return await client.get(url)
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.py")
        let funcs = symbols.filter { $0.kind == .function }
        XCTAssertEqual(funcs.count, 1)
        XCTAssertEqual(funcs[0].name, "fetch_data")
    }
}

final class RustSymbolExtractorTests: XCTestCase {
    let extractor = RustSymbolExtractor()

    func testExtractFn() {
        let source = """
        pub fn process(data: &[u8]) -> Result<()> {
            Ok(())
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.rs")
        let funcs = symbols.filter { $0.kind == .function }
        XCTAssertEqual(funcs.count, 1)
        XCTAssertEqual(funcs[0].name, "process")
    }

    func testExtractStruct() {
        let source = """
        pub struct Config {
            pub name: String,
            pub value: i32,
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.rs")
        let structs = symbols.filter { $0.kind == .struct }
        XCTAssertEqual(structs.count, 1)
        XCTAssertEqual(structs[0].name, "Config")
    }

    func testExtractEnum() {
        let source = """
        pub enum Color {
            Red,
            Green,
            Blue,
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.rs")
        let enums = symbols.filter { $0.kind == .enum }
        XCTAssertEqual(enums.count, 1)
        XCTAssertEqual(enums[0].name, "Color")
    }

    func testExtractTrait() {
        let source = """
        pub trait Drawable {
            fn draw(&self);
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.rs")
        let traits = symbols.filter { $0.kind == .protocol }
        XCTAssertEqual(traits.count, 1)
        XCTAssertEqual(traits[0].name, "Drawable")
    }

    func testExtractImpl() {
        let source = """
        impl Config {
            pub fn new() -> Self {
                Config { name: String::new(), value: 0 }
            }
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.rs")
        let extensions = symbols.filter { $0.kind == .extension }
        XCTAssertEqual(extensions.count, 1)
        XCTAssertEqual(extensions[0].name, "Config")
    }

    func testExtractUse() {
        let source = """
        use std::collections::HashMap;
        use crate::config::Config;
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.rs")
        let imports = symbols.filter { $0.kind == .import }
        XCTAssertEqual(imports.count, 2)
        XCTAssertTrue(imports.contains { $0.name == "std::collections::HashMap" })
    }
}

final class GoSymbolExtractorTests: XCTestCase {
    let extractor = GoSymbolExtractor()

    func testExtractFunc() {
        let source = """
        func main() {
            fmt.Println("Hello")
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "main.go")
        let funcs = symbols.filter { $0.kind == .function }
        XCTAssertEqual(funcs.count, 1)
        XCTAssertEqual(funcs[0].name, "main")
    }

    func testExtractTypeStruct() {
        let source = """
        type Server struct {
            Port int
            Host string
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "server.go")
        let structs = symbols.filter { $0.kind == .struct }
        XCTAssertEqual(structs.count, 1)
        XCTAssertEqual(structs[0].name, "Server")
    }

    func testExtractTypeInterface() {
        let source = """
        type Handler interface {
            Handle(ctx context.Context) error
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "handler.go")
        let interfaces = symbols.filter { $0.kind == .interface }
        XCTAssertEqual(interfaces.count, 1)
        XCTAssertEqual(interfaces[0].name, "Handler")
    }

    func testExtractMethodWithReceiver() {
        let source = """
        func (s *Server) Start() error {
            return nil
        }
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "server.go")
        let methods = symbols.filter { $0.kind == .method }
        XCTAssertEqual(methods.count, 1)
        XCTAssertEqual(methods[0].name, "Start")
    }

    func testExtractPackage() {
        let source = """
        package main
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "main.go")
        let modules = symbols.filter { $0.kind == .module }
        XCTAssertEqual(modules.count, 1)
        XCTAssertEqual(modules[0].name, "main")
    }
}

final class RubySymbolExtractorTests: XCTestCase {
    let extractor = RubySymbolExtractor()

    func testExtractDef() {
        let source = """
        def greet(name)
          puts "Hello #{name}"
        end
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.rb")
        let funcs = symbols.filter { $0.kind == .function }
        XCTAssertEqual(funcs.count, 1)
        XCTAssertEqual(funcs[0].name, "greet")
    }

    func testExtractClass() {
        let source = """
        class User < ActiveRecord::Base
          def name
            @name
          end
        end
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.rb")
        let classes = symbols.filter { $0.kind == .class }
        XCTAssertEqual(classes.count, 1)
        XCTAssertEqual(classes[0].name, "User")

        let methods = symbols.filter { $0.kind == .method }
        XCTAssertEqual(methods.count, 1)
        XCTAssertEqual(methods[0].scope, "User")
    }

    func testExtractModule() {
        let source = """
        module Authentication
          def authenticate(user)
            true
          end
        end
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.rb")
        let modules = symbols.filter { $0.kind == .module }
        XCTAssertEqual(modules.count, 1)
        XCTAssertEqual(modules[0].name, "Authentication")
    }

    func testExtractAttrAccessor() {
        let source = """
        class Person
          attr_accessor :name
          attr_reader :age
        end
        """
        let symbols = extractor.extractSymbols(from: source, filePath: "test.rb")
        let properties = symbols.filter { $0.kind == .property }
        XCTAssertEqual(properties.count, 2)
        XCTAssertTrue(properties.contains { $0.name == "name" })
        XCTAssertTrue(properties.contains { $0.name == "age" })
    }
}

final class SymbolExtractorEdgeCaseTests: XCTestCase {
    func testEmptySourceReturnsEmpty() {
        let extractor = SwiftSymbolExtractor()
        let symbols = extractor.extractSymbols(from: "", filePath: "empty.swift")
        XCTAssertTrue(symbols.isEmpty)
    }

    func testUnknownLanguageReturnsNil() {
        let registry = SymbolExtractorRegistry.shared
        XCTAssertNil(registry.extractor(for: .html))
        XCTAssertNil(registry.extractor(for: .css))
        XCTAssertNil(registry.extractor(for: .json))
        XCTAssertNil(registry.extractor(for: .markdown))
    }

    func testRegistryReturnsSupportedLanguages() {
        let registry = SymbolExtractorRegistry.shared
        XCTAssertNotNil(registry.extractor(for: .swift))
        XCTAssertNotNil(registry.extractor(for: .typescript))
        XCTAssertNotNil(registry.extractor(for: .javascript))
        XCTAssertNotNil(registry.extractor(for: .python))
        XCTAssertNotNil(registry.extractor(for: .rust))
        XCTAssertNotNil(registry.extractor(for: .go))
        XCTAssertNotNil(registry.extractor(for: .ruby))
    }
}

// MARK: - SymbolIndex Tests

final class SymbolIndexTests: XCTestCase {
    func testIndexFileAndQuerySymbols() async {
        let index = SymbolIndex()
        let source = """
        func hello() {}
        struct World {}
        """
        await index.indexSource(source, filePath: "/test/file.swift", language: .swift)

        let symbols = await index.symbols(inFile: "/test/file.swift")
        XCTAssertEqual(symbols.count, 2)
        XCTAssertTrue(symbols.contains { $0.name == "hello" })
        XCTAssertTrue(symbols.contains { $0.name == "World" })
    }

    func testFindByName() async {
        let index = SymbolIndex()
        await index.indexSource(
            "func process() {}\nfunc transform() {}",
            filePath: "/test/a.swift", language: .swift
        )
        await index.indexSource(
            "func process() {}",
            filePath: "/test/b.swift", language: .swift
        )

        let results = await index.find(name: "process", kind: nil)
        XCTAssertEqual(results.count, 2)

        let noResults = await index.find(name: "nonexistent", kind: nil)
        XCTAssertTrue(noResults.isEmpty)
    }

    func testFindByKindFilters() async {
        let index = SymbolIndex()
        await index.indexSource(
            "func process() {}\nstruct Process {}",
            filePath: "/test/file.swift", language: .swift
        )

        let funcsOnly = await index.find(name: "process", kind: .function)
        XCTAssertEqual(funcsOnly.count, 1)
        XCTAssertEqual(funcsOnly[0].kind, .function)

        // "Process" struct won't match "process" (case sensitive name match)
        let structsOnly = await index.find(name: "Process", kind: .struct)
        XCTAssertEqual(structsOnly.count, 1)
    }

    func testFuzzySearch() async {
        let index = SymbolIndex()
        await index.indexSource(
            "func handleRequest() {}\nfunc handleResponse() {}\nfunc processData() {}",
            filePath: "/test/file.swift", language: .swift
        )

        let results = await index.find(query: "handle")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.name.lowercased().contains("handle") })
    }

    func testReferencesFindsUsages() async {
        let index = SymbolIndex()
        let source = """
        func greet() {}
        func main() {
            greet()
            print("calling greet")
        }
        """
        await index.indexSource(source, filePath: "/test/file.swift", language: .swift)

        let refs = await index.references(to: "greet")
        // Should find references on lines that use "greet" but are not the definition
        XCTAssertFalse(refs.isEmpty)
        // The definition is on line 1; references should be on other lines
        XCTAssertTrue(refs.allSatisfy { $0.line != 1 })
    }

    func testClearEmptiesIndex() async {
        let index = SymbolIndex()
        await index.indexSource(
            "func hello() {}",
            filePath: "/test/file.swift", language: .swift
        )
        let countBefore = await index.totalSymbols
        XCTAssertGreaterThan(countBefore, 0)

        await index.clear()
        let countAfter = await index.totalSymbols
        XCTAssertEqual(countAfter, 0)
    }

    func testTotalSymbolsCountsAllFiles() async {
        let index = SymbolIndex()
        await index.indexSource(
            "func a() {}\nfunc b() {}",
            filePath: "/test/a.swift", language: .swift
        )
        await index.indexSource(
            "func c() {}",
            filePath: "/test/b.swift", language: .swift
        )

        let total = await index.totalSymbols
        XCTAssertEqual(total, 3)
    }

    func testRemoveFileUpdatesIndex() async {
        let index = SymbolIndex()
        await index.indexSource(
            "func hello() {}",
            filePath: "/test/file.swift", language: .swift
        )
        let before = await index.totalSymbols
        XCTAssertEqual(before, 1)

        await index.removeFile("/test/file.swift")
        let after = await index.totalSymbols
        XCTAssertEqual(after, 0)
    }

    func testReindexReplacesOldSymbols() async {
        let index = SymbolIndex()
        await index.indexSource(
            "func oldFunc() {}",
            filePath: "/test/file.swift", language: .swift
        )
        // Re-index with different content
        await index.indexSource(
            "func newFunc() {}",
            filePath: "/test/file.swift", language: .swift
        )

        let symbols = await index.symbols(inFile: "/test/file.swift")
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].name, "newFunc")

        let oldResults = await index.find(name: "oldFunc", kind: nil)
        XCTAssertTrue(oldResults.isEmpty)
    }
}

// MARK: - SemanticChunker Tests

final class SemanticChunkerTests: XCTestCase {
    let chunker = SemanticChunker()

    func testChunkSwiftAtFunctionBoundaries() {
        let source = """
        import Foundation

        func hello() {
            print("hello")
        }

        func world() {
            print("world")
        }
        """
        let chunks = chunker.chunk(source: source, language: .swift, filePath: "test.swift")
        XCTAssertGreaterThanOrEqual(chunks.count, 2)

        // Should have import chunk and function chunks
        let functionChunks = chunks.filter { $0.kind == .function }
        XCTAssertEqual(functionChunks.count, 2)
        XCTAssertTrue(functionChunks.contains { $0.name == "hello" })
        XCTAssertTrue(functionChunks.contains { $0.name == "world" })
    }

    func testChunkPythonAtDefBoundaries() {
        let source = """
        import os

        def greet(name):
            print(f"Hello {name}")

        def farewell(name):
            print(f"Goodbye {name}")
        """
        let chunks = chunker.chunk(source: source, language: .python, filePath: "test.py")
        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        let functionChunks = chunks.filter { $0.kind == .function }
        XCTAssertEqual(functionChunks.count, 2)
    }

    func testTokenEstimateIsReasonable() {
        let source = String(repeating: "abcd", count: 100) // 400 chars
        let chunks = chunker.chunk(source: source, language: .swift, filePath: "test.swift")
        // All chunks combined should have a reasonable total estimate
        let totalEstimate = chunks.reduce(0) { $0 + $1.tokenEstimate }
        // 400 chars / 4 chars per token = 100 tokens
        XCTAssertGreaterThan(totalEstimate, 50)
        XCTAssertLessThan(totalEstimate, 200)
    }

    func testUnknownLanguageFallsBackToLineChunking() {
        let lines = (1...250).map { "line \($0)" }
        let source = lines.joined(separator: "\n")
        let chunks = chunker.chunk(source: source, language: .html, filePath: "test.html")

        // 250 lines / 100 lines per chunk = 3 chunks
        XCTAssertEqual(chunks.count, 3)
        XCTAssertTrue(chunks.allSatisfy { $0.kind == .block })
    }

    func testEmptySourceReturnsSingleChunk() {
        let chunks = chunker.chunk(source: "", language: .swift, filePath: "empty.swift")
        // Empty source with no symbols -> fallback -> single chunk
        XCTAssertEqual(chunks.count, 1)
    }

    func testChunkClassWithMethods() {
        let source = """
        class Calculator {
            func add(a: Int, b: Int) -> Int { a + b }
            func subtract(a: Int, b: Int) -> Int { a - b }
        }
        """
        let chunks = chunker.chunk(source: source, language: .swift, filePath: "calc.swift")
        // Class is a boundary, so we should get at least 1 chunk
        XCTAssertGreaterThanOrEqual(chunks.count, 1)
        let classChunks = chunks.filter { $0.kind == .class_ }
        XCTAssertEqual(classChunks.count, 1)
        XCTAssertEqual(classChunks[0].name, "Calculator")
    }

    func testChunkPreservesContent() {
        let source = """
        func example() {
            let x = 42
            return x
        }
        """
        let chunks = chunker.chunk(source: source, language: .swift, filePath: "test.swift")
        // Content of all chunks should cover the entire source
        let allContent = chunks.map(\.content).joined(separator: "\n")
        XCTAssertTrue(allContent.contains("let x = 42"))
    }
}

// MARK: - SemanticSearch Tests

final class SemanticSearchTests: XCTestCase {
    let search = SemanticSearch()

    func testExactNameMatchRanksHighest() async {
        let index = SymbolIndex()
        await index.indexSource(
            "func processData() {}\nfunc processItems() {}\nfunc transform() {}",
            filePath: "/test/file.swift", language: .swift
        )

        let results = await search.search(query: "processData", index: index, limit: 10)
        XCTAssertFalse(results.isEmpty)
        // Exact match should be first
        XCTAssertEqual(results[0].symbol?.name, "processData")
        XCTAssertEqual(results[0].score, 1.0)
    }

    func testPrefixMatchRanksAboveContains() async {
        let index = SymbolIndex()
        await index.indexSource(
            "func handleRequest() {}\nfunc requestHandler() {}",
            filePath: "/test/file.swift", language: .swift
        )

        let results = await search.search(query: "handle", index: index, limit: 10)
        XCTAssertFalse(results.isEmpty)
        // "handleRequest" starts with "handle" -> prefix match (0.8)
        // "requestHandler" contains "handle" -> contains match (0.6)
        if results.count >= 2 {
            XCTAssertGreaterThan(results[0].score, results[1].score)
        }
    }

    func testEmptyQueryReturnsEmpty() async {
        let index = SymbolIndex()
        await index.indexSource(
            "func hello() {}",
            filePath: "/test/file.swift", language: .swift
        )

        let results = await search.search(query: "", index: index, limit: 10)
        XCTAssertTrue(results.isEmpty)

        let whitespaceResults = await search.search(query: "   ", index: index, limit: 10)
        XCTAssertTrue(whitespaceResults.isEmpty)
    }

    func testLimitIsRespected() async {
        let index = SymbolIndex()
        let source = (1...20).map { "func func\($0)() {}" }.joined(separator: "\n")
        await index.indexSource(source, filePath: "/test/file.swift", language: .swift)

        let results = await search.search(query: "func", index: index, limit: 5)
        XCTAssertLessThanOrEqual(results.count, 5)
    }

    func testSearchWithChunks() async {
        let index = SymbolIndex()
        await index.indexSource(
            "func hello() {}",
            filePath: "/test/file.swift", language: .swift
        )

        let chunks = [
            CodeChunk(
                filePath: "/test/other.swift",
                startLine: 1, endLine: 5,
                kind: .function, name: "processAuth",
                content: "func processAuth() {\n    let auth = authenticate()\n}",
                tokenEstimate: 12
            ),
        ]

        let results = await search.search(
            query: "auth",
            index: index,
            chunks: chunks,
            limit: 10
        )
        // Should find chunk-level match
        XCTAssertFalse(results.isEmpty)
    }

    func testResultsContainSnippets() async {
        let index = SymbolIndex()
        await index.indexSource(
            "public func calculateTotal(items: [Item]) -> Double {}",
            filePath: "/test/calc.swift", language: .swift
        )

        let results = await search.search(query: "calculateTotal", index: index, limit: 5)
        XCTAssertFalse(results.isEmpty)
        XCTAssertFalse(results[0].snippet.isEmpty)
    }
}

// MARK: - CodeDependencyGraph Tests

final class CodeDependencyGraphTests: XCTestCase {
    func testBuildFromSymbolsWithImports() {
        let symbols = [
            Symbol(name: "Foundation", kind: .import, filePath: "/src/App.swift", line: 1, column: 1),
            Symbol(name: "start", kind: .function, filePath: "/src/App.swift", line: 3, column: 1),
            Symbol(name: "Foundation", kind: .import, filePath: "/src/Util.swift", line: 1, column: 1),
            Symbol(name: "helper", kind: .function, filePath: "/src/Util.swift", line: 3, column: 1),
        ]
        let files = [
            FileSnapshot(path: "/src/App.swift", relativePath: "App.swift", size: 100, modificationDate: Date(), isDirectory: false),
            FileSnapshot(path: "/src/Util.swift", relativePath: "Util.swift", size: 80, modificationDate: Date(), isDirectory: false),
        ]

        let graph = CodeDependencyGraph.build(from: symbols, files: files)
        XCTAssertGreaterThanOrEqual(graph.moduleCount, 2)
        XCTAssertGreaterThan(graph.edgeCount, 0)

        // Both App and Util import Foundation
        let foundationImporters = graph.importedBy("Foundation")
        XCTAssertTrue(foundationImporters.contains("App"))
        XCTAssertTrue(foundationImporters.contains("Util"))
    }

    func testModulesAreDeduplicated() {
        let symbols = [
            Symbol(name: "UIKit", kind: .import, filePath: "/src/A.swift", line: 1, column: 1),
            Symbol(name: "UIKit", kind: .import, filePath: "/src/B.swift", line: 1, column: 1),
        ]
        let files = [
            FileSnapshot(path: "/src/A.swift", relativePath: "A.swift", size: 50, modificationDate: Date(), isDirectory: false),
            FileSnapshot(path: "/src/B.swift", relativePath: "B.swift", size: 50, modificationDate: Date(), isDirectory: false),
        ]

        let graph = CodeDependencyGraph.build(from: symbols, files: files)
        // UIKit should appear only once as a module
        let uikitModules = graph.modules.filter { $0.id == "UIKit" }
        XCTAssertEqual(uikitModules.count, 1)
    }

    func testEdgeCreationFromImports() {
        let symbols = [
            Symbol(name: "Config", kind: .import, filePath: "/src/App.swift", line: 1, column: 1),
            Symbol(name: "run", kind: .function, filePath: "/src/App.swift", line: 3, column: 1),
            Symbol(name: "Settings", kind: .struct, filePath: "/src/Config.swift", line: 1, column: 1),
        ]
        let files = [
            FileSnapshot(path: "/src/App.swift", relativePath: "App.swift", size: 100, modificationDate: Date(), isDirectory: false),
            FileSnapshot(path: "/src/Config.swift", relativePath: "Config.swift", size: 80, modificationDate: Date(), isDirectory: false),
        ]

        let graph = CodeDependencyGraph.build(from: symbols, files: files)
        // App imports Config -> there should be an edge
        let appImports = graph.imports(of: "App")
        XCTAssertTrue(appImports.contains("Config"))
    }

    func testEmptySymbolsProducesEmptyGraph() {
        let graph = CodeDependencyGraph.build(from: [], files: [])
        XCTAssertEqual(graph.moduleCount, 0)
        XCTAssertEqual(graph.edgeCount, 0)
    }

    func testNoSelfEdges() {
        // If a file named "Foundation.swift" imports Foundation, there should be no self-edge
        let symbols = [
            Symbol(name: "Foundation", kind: .import, filePath: "/src/Foundation.swift", line: 1, column: 1),
        ]
        let files = [
            FileSnapshot(path: "/src/Foundation.swift", relativePath: "Foundation.swift", size: 50, modificationDate: Date(), isDirectory: false),
        ]

        let graph = CodeDependencyGraph.build(from: symbols, files: files)
        let selfEdges = graph.edges.filter { $0.from == $0.to }
        XCTAssertTrue(selfEdges.isEmpty)
    }
}
