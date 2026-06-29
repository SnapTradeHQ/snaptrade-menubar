import Foundation

protocol TokenStore {
    func load() throws -> TokenSet?
    func save(_ tokenSet: TokenSet) throws
    func delete() throws
}
