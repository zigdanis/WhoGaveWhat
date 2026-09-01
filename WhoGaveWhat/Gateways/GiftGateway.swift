import Foundation

@MainActor
protocol GiftGateway: AnyObject {
    func loadGifts() throws -> [Gift]
    func save(_ gift: Gift) throws
    func deleteGift(id: String) throws
}
