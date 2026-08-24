@MainActor
struct DeleteGiftUseCase {
    let gateway: GiftGateway

    func execute(id: String) throws {
        try gateway.deleteGift(id: id)
    }
}
