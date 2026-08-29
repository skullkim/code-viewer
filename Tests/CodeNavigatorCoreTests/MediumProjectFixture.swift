import Foundation

/// The medium repository REQ-NF-001 names (~5,000 source files), built once in one place.
///
/// Indexing and search performance have to be measured against the *same* corpus, or a change
/// that speeds one up while slowing the other down looks like an improvement in both suites.
enum MediumProjectFixture {
    /// Builds a repository of roughly the size the requirement names.
    static func make(fileCount: Int) -> TemporaryProjectFixture {
        let fixture = TemporaryProjectFixture()
        let languages = ["kt", "java", "ts", "js"]

        for index in 0..<fileCount {
            let fileExtension = languages[index % languages.count]
            let body: String
            switch fileExtension {
            case "kt":
                body = """
                package com.example.module\(index % 50)

                class Service\(index)(private val repository: Repository\(index)) {
                    val identifier: Int = \(index)
                    fun handle(request: String): Boolean {
                        return repository.store(request)
                    }
                    fun describe(): String = "service-\(index)"
                }

                interface Repository\(index) {
                    fun store(value: String): Boolean
                }
                """
            case "java":
                body = """
                package com.example.module\(index % 50);

                public class Handler\(index) {
                    private final String name;
                    public Handler\(index)(String name) { this.name = name; }
                    public boolean handle(String request) { return true; }
                }
                """
            case "ts":
                body = """
                export interface Options\(index) { limit: number; }
                export class Controller\(index) {
                  private cache = new Map<string, number>();
                  handle(request: string): boolean { return true; }
                }
                export const build\(index) = (value: number) => value + \(index);
                """
            default:
                body = """
                export class Widget\(index) {
                  count = \(index);
                  render = () => this.count;
                  update(next) { this.count = next; }
                }
                export const make\(index) = (n) => new Widget\(index)(n);
                """
            }
            fixture.write("src/module\(index % 50)/File\(index).\(fileExtension)", contents: body)
        }
        return fixture
    }
}
