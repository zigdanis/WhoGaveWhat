import Foundation
import CoreData

/// A person record — covers both family members (`isFamily == true`) and
/// external friends/relatives (`isFamily == false`).
@objc(CDPerson)
public final class CDPerson: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDPerson> {
        NSFetchRequest<CDPerson>(entityName: "CDPerson")
    }

    @NSManaged public var id: String?
    @NSManaged public var name: String?
    @NSManaged public var colorHex: Int64
    @NSManaged public var isFamily: Bool
    @NSManaged public var sortIndex: Int64
    @NSManaged public var giftsAsPerson: NSSet?
    @NSManaged public var giftsAsMember: NSSet?
}

/// A single tracked gift.
@objc(CDGift)
public final class CDGift: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDGift> {
        NSFetchRequest<CDGift>(entityName: "CDGift")
    }

    @NSManaged public var id: String?
    @NSManaged public var emoji: String?
    @NSManaged public var name: String?
    @NSManaged public var flow: String?
    @NSManaged public var celebration: String?
    @NSManaged public var date: Date?
    @NSManaged public var value: Double
    @NSManaged public var paidByYou: Bool
    @NSManaged public var person: CDPerson?   // external party
    @NSManaged public var member: CDPerson?   // family member
}
