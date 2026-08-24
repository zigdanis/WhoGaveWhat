@MainActor
struct LoadGiftsUseCase {
    let gateway: GiftGateway

    func execute() throws -> [Gift] {
        try gateway.loadGifts()
    }
}
